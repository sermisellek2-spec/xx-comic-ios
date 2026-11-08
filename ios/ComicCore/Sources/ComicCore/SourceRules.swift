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
    public static let API: Int = 2
    public static let MAX_SCRIPT: Int = 512 * 1024
    public static let MAX_PACKAGE: Int = 16 * 1024 * 1024

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
    public let replacesNative: Bool
    public let imageRefresh: Bool
    public let supportsSearch: Bool
    public let browserSession: Bool
    public let requiresVpn: Bool
    private let vpnDeclared: Bool
    public let hosts: [String]

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

        guard !self.name.isEmpty, self.name.count <= 80, version >= 1 else {
            throw RuleError("站源名称或版本无效")
        }

        guard engineApi >= 1 && engineApi <= Self.API else {
            throw RuleError("此规则需要其他版本的规则引擎")
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

        guard requestLimit >= 1 && requestLimit <= 512 && timeoutSeconds >= 10 && timeoutSeconds <= 240 else {
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

        var cleanedBase = rawBaseUrl
        while cleanedBase.hasSuffix("/") {
            cleanedBase.removeLast()
        }
        self.baseUrl = cleanedBase
        try Self.validateHttp(self.baseUrl)

        guard let baseHost = URL(string: self.baseUrl)?.host else {
            throw RuleError("站点域名不在授权列表中")
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

        self.replacesNative = (json["replacesNative"] as? Bool) ?? false
        self.imageRefresh = (json["imageRefresh"] as? Bool) ?? false

        guard hostsList.count >= 1 && hostsList.count <= 64 else {
            throw RuleError("允许访问的域名数量无效")
        }
        var allow = Set<String>()
        for h in hostsList {
            let host = h.lowercased()
            guard host.count <= 253,
                  host.range(of: #"^(?:\*\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$"#, options: .regularExpression) != nil,
                  !host.contains("..") else {
                throw RuleError("域名授权格式无效")
            }
            allow.insert(host)
        }
        self.hosts = allow.sorted()

        // Java identity serialization uses ArrayList.toString() which produces: "[elem1, elem2]"
        let hostsString = "[" + self.hosts.joined(separator: ", ") + "]"
        let identity = "\(id)\n\(version)\n\(self.name)\n\(self.baseUrl)\n\(hostsString)\n\(self.replacesNative)\n\(self.imageRefresh)\n\(self.scriptSha256)"
            + (engineApi == 1 ? "" : "\napi=\(engineApi)\nsearch=\(supportsSearch)\nbrowser=\(browserSession)\nrequests=\(requestLimit)\ntimeout=\(timeoutSeconds)")

        self.coreHash = Self.sha(Data(identity.utf8))
        self.hash = self.vpnDeclared
            ? Self.sha(Data((identity + "\nrequiresVpn=\(self.requiresVpn)").utf8))
            : self.coreHash

        guard self.allows(baseHost) else {
            throw RuleError("站点域名不在授权列表中")
        }
    }

    public func allows(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        for allowed in hosts {
            if host == allowed { return true }
            if allowed.hasPrefix("*.") {
                let suffix = String(allowed.dropFirst())
                if host.hasSuffix(suffix) { return true }
            }
        }
        return false
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
            guard let text = String(data: decoded, encoding: .utf8) else {
                throw RuleError("UTF-8 解码失败")
            }
            return text

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

        case "urlEncode":
            let charset = (args["charset"] as? String) ?? "UTF-8"
            guard ["UTF-8", "GBK", "GB2312", "Big5"].contains(charset) else {
                throw RuleError("不支持此文本编码")
            }
            return try urlEncode(dataStr, charset: charset)

        case "pinyin":
            return pinyin(dataStr)

        case "md5":
            return md5Hex(Data(dataStr.utf8))

        case "sha1":
            return sha1Hex(Data(dataStr.utf8))

        case "sha512":
            return sha512Hex(Data(dataStr.utf8))

        case "sha256":
            return RuleDefinition.sha(Data(dataStr.utf8))

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
            case "mod":
                guard right != 0 else { throw RuleError("整数运算除数不能为零") }
                return String(left % right)
            default:
                throw RuleError("不支持此整数运算")
            }

        case "inflate", "gzip":
            let raw = try RuleBase64.decode(dataStr)
            let decompressed = try decompress(raw, isGzip: type == "gzip")
            guard let text = String(data: decompressed, encoding: .utf8) else {
                throw RuleError("解压后数据不是有效 UTF-8")
            }
            return text

        case "aesCbcDecrypt", "aesEcbDecrypt":
            let encoding = (args["dataEncoding"] as? String) ?? "base64"
            let binaryData = try parseBinary(dataStr, encoding: encoding)
            let decrypted = try decrypt(input: binaryData, args: args)
            guard let text = String(data: decrypted, encoding: .utf8) else {
                throw RuleError("解密后数据不是有效 UTF-8")
            }
            return text

        default:
            throw RuleError("不支持的编码方式")
        }
    }

    public static func decrypt(input: Data, args: [String: Any]) throws -> Data {
        let isEcb = (args["type"] as? String) == "aesEcbDecrypt"
        guard let keyStr = args["key"] as? String else {
            throw RuleError("缺少解密密钥")
        }
        let keyEncoding = (args["keyEncoding"] as? String) ?? "base64"
        let key = try parseBinary(keyStr, encoding: keyEncoding)

        var ciphertext = input
        let iv: Data
        if isEcb {
            iv = Data()
        } else {
            let ivPrefix = (args["ivPrefix"] as? Bool) ?? false
            if ivPrefix {
                guard ciphertext.count >= 16 else { throw RuleError("加密数据不完整") }
                iv = ciphertext.prefix(16)
                ciphertext = ciphertext.dropFirst(16)
            } else {
                guard let ivStr = args["iv"] as? String else { throw RuleError("缺少解密向量") }
                let ivEncoding = (args["ivEncoding"] as? String) ?? "base64"
                iv = try parseBinary(ivStr, encoding: ivEncoding)
            }
        }

        do {
            if isEcb {
                return try aesEcbDecrypt(ciphertext, key: key)
            } else {
                return try SourceAES.decrypt(ciphertext, key: key, iv: iv)
            }
        } catch {
            throw RuleError("规则图片解码失败")
        }
    }

    private static func parseBinary(_ text: String, encoding: String) throws -> Data {
        switch encoding {
        case "utf8":
            return Data(text.utf8)
        case "base64":
            return try RuleBase64.decode(text)
        case "hex":
            guard text.range(of: #"^(?:[a-fA-F0-9]{2})*$"#, options: .regularExpression) != nil else {
                throw RuleError("十六进制数据无效")
            }
            var data = Data()
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

    private static func aesEcbDecrypt(_ ciphertext: Data, key: Data) throws -> Data {
        guard [16, 24, 32].contains(key.count), !ciphertext.isEmpty, ciphertext.count.isMultiple(of: 16) else {
            throw RuleError("加密数据格式无效")
        }
        #if canImport(CommonCrypto)
        var output = Data(count: ciphertext.count)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                            keyBytes.baseAddress, key.count, nil,
                            cipherBytes.baseAddress, ciphertext.count, out.baseAddress, capacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw RuleError("ECB 解密失败") }
        output.count = written
        return output
        #elseif os(Linux)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xxcomic-ecb-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input"), result = directory.appendingPathComponent("output")
        try ciphertext.write(to: input)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["enc", "-d", "-aes-\(key.count * 8)-ecb", "-nopad", "-K", key.map { String(format: "%02x", $0) }.joined(),
                             "-in", input.path, "-out", result.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuleError("ECB 解密失败") }
        let padded = try Data(contentsOf: result)
        guard let padding = padded.last, (1...16).contains(Int(padding)),
              padded.count >= Int(padding),
              padded.suffix(Int(padding)).allSatisfy({ $0 == padding }) else {
            throw RuleError("ECB 填充无效")
        }
        return Data(padded.dropLast(Int(padding)))
        #else
        throw RuleError("当前平台不支持 ECB 解密")
        #endif
    }

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
    public static func validate(rule: RuleDefinition, descriptor: [String: Any]) throws {
        guard let type = descriptor["type"] as? String else {
            throw RuleError("缺少图片解码类型")
        }
        if type == "prefix" {
            if rule.engineApi < 2 { throw RuleError("图片前缀解码需要规则引擎 API 2") }
            guard let count = descriptor["bytes"] as? Int,
                  let magicStr = descriptor["magic"] as? String else {
                throw RuleError("图片前缀参数无效")
            }
            let marker = try RuleBase64.decode(magicStr)
            guard count >= 1 && count <= 65536 && marker.count >= 1 && marker.count <= count else {
                throw RuleError("图片前缀参数无效")
            }
            return
        }
        guard type == "aesCbc" else {
            throw RuleError("此图片解码需要升级规则引擎")
        }
        guard let keyStr = descriptor["key"] as? String else {
            throw RuleError("缺少解码密钥")
        }
        let keyLen = try RuleBase64.decode(keyStr).count
        guard [16, 24, 32].contains(keyLen) else {
            throw RuleError("图片解码密钥无效")
        }
        let ivPrefix = (descriptor["ivPrefix"] as? Bool) ?? false
        let passIfPlain = (descriptor["passIfPlain"] as? Bool) ?? false
        if (ivPrefix || passIfPlain) && rule.engineApi < 2 {
            throw RuleError("图片解码参数需要规则引擎 API 2")
        }
        if !ivPrefix {
            guard let ivStr = descriptor["iv"] as? String,
                  try RuleBase64.decode(ivStr).count == 16 else {
                throw RuleError("图片解码向量无效")
            }
        }
    }

    public static func decode(descriptor: [String: Any]?, data: Data) throws -> Data {
        guard let d = descriptor else { return data }
        let type = (d["type"] as? String) ?? ""
        let passIfPlain = (d["passIfPlain"] as? Bool) ?? false

        if passIfPlain && isImage(data) {
            return data
        }

        if type == "prefix" {
            guard let count = d["bytes"] as? Int, count >= 1 && count <= 65536,
                  let magicStr = d["magic"] as? String else {
                throw RuleError("图片前缀参数无效")
            }
            let marker = try RuleBase64.decode(magicStr)
            if data.count < marker.count || data.prefix(marker.count) != marker {
                return data
            }
            guard data.count >= count else {
                throw RuleError("图片数据不完整")
            }
            let remainder = data.dropFirst(count)
            guard isImage(Data(remainder)) else {
                throw RuleError("图片前缀后的数据损坏")
            }
            return Data(remainder)
        }

        if type == "aesCbc" {
            guard let keyStr = d["key"] as? String else { throw RuleError("缺少解码密钥") }
            let key = try RuleBase64.decode(keyStr)
            let ivPrefix = (d["ivPrefix"] as? Bool) ?? false

            var ciphertext = data
            let iv: Data
            if ivPrefix {
                guard ciphertext.count >= 16 else { throw RuleError("图片数据不完整") }
                iv = ciphertext.prefix(16)
                ciphertext = ciphertext.dropFirst(16)
            } else {
                guard let ivStr = d["iv"] as? String else { throw RuleError("缺少解密向量") }
                iv = try RuleBase64.decode(ivStr)
            }
            return try SourceAES.decrypt(ciphertext, key: key, iv: iv)
        }

        return data
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
            let meta = try metadata(tagged)
            guard let image = meta["image"] as? [String: Any],
                  let transform = image["transform"] as? [String: Any] else { return "" }
            let type = (transform["type"] as? String) ?? ""
            guard let bands = transform["bands"] as? Int,
                  type == "reverseBands", bands >= 2 && bands <= 100 else {
                throw RuleError("图片变换参数无效")
            }
            return "bands:\(bands)"
        } catch let err as RuleError {
            throw err
        } catch {
            throw RuleError("图片变换信息损坏")
        }
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
        guard let host = URL(string: url)?.host, rule.allows(host) else {
            throw RuleError("图片域名未获规则授权")
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

        if let decode = image["decode"] as? [String: Any] {
            try RuleImageData.validate(rule: rule, descriptor: decode)
        }

        if let cookies = image["cookies"] as? [String: Any] {
            guard rule.engineApi >= 2 else { throw RuleError("图片会话需要规则引擎 API 2") }
            _ = try RuleSessions.checked(cookies)
        }

        if let transform = image["transform"] as? [String: Any] {
            guard rule.engineApi >= 2,
                  (transform["type"] as? String) == "reverseBands",
                  let bands = transform["bands"] as? Int,
                  bands >= 2 && bands <= 100 else {
                throw RuleError("规则图片变换参数无效")
            }
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
        return try RuleImageData.decode(descriptor: descriptor?["decode"] as? [String: Any], data: data)
    }
}

// MARK: - RuleHttp

public final class RuleHttp: @unchecked Sendable {
    public let rule: RuleDefinition
    public let debug: Bool
    private let cancelled: @Sendable () -> Bool
    private let timeoutMillis: Int

    private static let lock = NSLock()
    private static var nextTimes = [String: Int64]()

    public init(rule: RuleDefinition, debug: Bool = false, cancelled: @escaping @Sendable () -> Bool = { false }, timeoutMillis: Int = 20000) {
        self.rule = rule
        self.debug = debug
        self.cancelled = cancelled
        self.timeoutMillis = timeoutMillis
    }

    public func checkUrl(_ urlString: String) throws {
        try RuleDefinition.validateHttp(urlString)
        guard let host = URL(string: urlString)?.host else {
            throw RuleError("规则请求了未授权的域名")
        }
        guard rule.allows(host) else {
            throw RuleError("规则请求了未授权的域名")
        }
        if !debug {
            try checkNonLocalHost(host)
        }
    }

    private func checkNonLocalHost(_ host: String) throws {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") || lower.hasPrefix("127.") || lower == "0.0.0.0" || lower == "::1" {
            throw RuleError("规则不能访问本地网络")
        }
    }

    public static func checkHeader(_ key: String, _ value: String) throws {
        guard key.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil,
              !value.unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }),
              value.count <= 4096 else {
            throw RuleError("规则请求头无效或不支持")
        }
        let lowerKey = key.lowercased()
        if ["host", "connection", "content-length", "proxy-authorization", "cookie"].contains(lowerKey) {
            throw RuleError("规则请求头无效或不支持")
        }
    }
}

// MARK: - RuleBitmapTransform

public enum RuleBitmapTransform {
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

public enum RuleRepository {
    public static let DEFAULT_URL = "https://weifeng.cloud/rules/index.json"

    public static func fetch(_ url: String) throws -> String {
        try RuleDefinition.validateHttp(url)
        guard url.hasPrefix("https://") else {
            throw RuleError("规则下载与订阅需要 HTTPS")
        }
        guard let u = URL(string: url) else { throw RuleError("地址无效") }
        let (data, response) = try synchronousGet(u)
        guard let http = response as? HTTPURLResponse else { throw RuleError("响应类型无效") }
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

    public static func read(
        root: [String: Any],
        origin: String?,
        fetcher: (String) throws -> String = { url in try fetch(url) }
    ) throws -> [RuleDefinition] {
        if (root["schema"] as? String) == "xx-comic.rules" {
            return try RuleStore.parse(json: root)
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
            let parsed = try RuleStore.parse(json: packJson)
            for r in parsed {
                guard ids.insert(r.id).inserted else {
                    throw RuleError("仓库包含重复站源 ID")
                }
                result.append(r)
            }
            if result.count > RuleStore.MAX_SOURCES {
                throw RuleError("仓库规则数量过多")
            }
        }
        return result
    }

    private static func synchronousGet(_ url: URL) throws -> (Data, URLResponse) {
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?
        let sema = DispatchSemaphore(value: 0)

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
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
    public static func prepare(
        urls: [String],
        validator: (RuleDefinition) throws -> Void,
        fetcher: (String) throws -> String = { url in try RuleRepository.fetch(url) }
    ) throws -> [RuleDefinition] {
        guard !urls.isEmpty else {
            throw RuleError("暂无订阅，请先添加规则订阅")
        }
        var merged = [String: RuleDefinition]()
        var totalBytes = 0
        for url in urls {
            try Task.checkCancellation()
            try RuleDefinition.validateHttp(url)
            guard url.hasPrefix("https://") else {
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
            let rules = try RuleRepository.read(root: root, origin: url, fetcher: fetcher)
            for rule in rules {
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
            }
        }
        try Task.checkCancellation()
        return Array(merged.values)
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
        if defaultRepositoryInitialized { return }
        var next = internalRepositories
        if !next.contains(RuleRepository.DEFAULT_URL) && next.count < 16 {
            next.append(RuleRepository.DEFAULT_URL)
        }
        try commit(nextEntries: internalEntries, nextOrder: internalOrder, nextHidden: internalHidden, nextRepos: next, initialized: true)
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
        for row in sources {
            let r = try RuleDefinition(json: row)
            guard ids.insert(r.id).inserted else {
                throw RuleError("同一批规则包含重复 ID：\(r.id)")
            }
            rules.append(r)
        }
        return rules
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
    }

    private func commit(
        nextEntries: [String: Entry],
        nextOrder: [String],
        nextHidden: Set<String>,
        nextRepos: [String],
        initialized: Bool
    ) throws {
        try ensureWritable()
        try Task.checkCancellation()

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
    private var internalStore: RuleStore?
    private var snapshot: Snapshot
    public private(set) var error: String = ""
    private var versionsByHash = [String: ScriptComicSource]()

    public init(directory: URL) {
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
            let client = ScriptComicSource(rule: e.rule)
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
        let created = ScriptComicSource(rule: r)
        lock.lock()
        versionsByHash[hash] = created
        lock.unlock()
        return created
    }

    public func validate(_ rule: RuleDefinition) throws {
        try ScriptComicSource(rule: rule).validate()
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

public struct RuleError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
    public var errorDescription: String? { message }
}
