import Foundation

public enum PublicSourceImages {
    private static let mark = "#xx-public="

    public static func tag(_ url: String, _ source: String, _ page: String, _ index: Int) -> String {
        guard !url.isEmpty else { return "" }
        let encodedPage = formURLEncode(page)
        return strip(url) + mark + source + "|" + encodedPage + "|" + String(index)
    }

    static func metadata(_ url: String) -> [String] {
        guard let range = url.range(of: mark) else { return [] }
        let tail = String(url[range.upperBound...])
        let parts = tail.components(separatedBy: "|")
        guard parts.count == 3, PublicSourceRegistry.contains(parts[0]), Int(parts[2]) != nil else {
            return []
        }
        let decodedPage = formURLDecode(parts[1])
        return [parts[0], decodedPage, parts[2]]
    }

    public static func sourceId(_ url: String) -> String {
        let m = metadata(url)
        return m.count == 3 ? m[0] : ""
    }

    public static func referer(_ url: String, fallback: String = "") -> String {
        let m = metadata(url)
        return m.count == 3 ? m[1] : fallback
    }

    public static func strip(_ url: String) -> String {
        guard let idx = url.firstIndex(of: "#") else { return url }
        return String(url[..<idx])
    }

    public static func cacheIdentity(_ url: String) -> String {
        let m = metadata(url)
        guard m.count == 3, let idx = Int(m[2]) else { return strip(url) }
        return idx >= 0 ? "public:\(m[0]):\(m[1]):\(m[2])" : "public:\(m[0]):cover:\(strip(url))"
    }

    public static func decode(_ data: Data, tagged url: String) throws -> Data {
        try decode(url, data)
    }

    public static func decode(_ url: String, _ data: Data) throws -> Data {
        let m = metadata(url)
        guard m.count == 3,
              let profile = try? PublicSourceRegistry.profile(m[0]),
              profile.family == "fav" else {
            return data
        }
        let key = try b64("NlgrYjYuRT5ic1hifSs9Tg==")
        return try decryptData(data, key: key)
    }

    public static func decodeForSource(sourceId: String, url: String, data: Data) throws -> Data {
        if !Self.sourceId(url).isEmpty {
            return try decode(url, data)
        }
        guard PublicSourceRegistry.contains(sourceId),
              let profile = try? PublicSourceRegistry.profile(sourceId),
              profile.family == "fav" else {
            return data
        }
        let key = try b64("NlgrYjYuRT5ic1hifSs9Tg==")
        return try decryptData(data, key: key)
    }

    static func decryptData(_ input: Data, key: Data) throws -> Data {
        guard input.count > 16 else {
            throw NSError(domain: "PublicSourceImages", code: 1, userInfo: [NSLocalizedDescriptionKey: "图片数据不完整"])
        }
        let iv = Data(input.prefix(16))
        let cipher = Data(input.dropFirst(16))
        do {
            return try SourceAES.decrypt(cipher, key: key, iv: iv)
        } catch {
            throw NSError(domain: "PublicSourceImages", code: 2, userInfo: [NSLocalizedDescriptionKey: "图片解码失败"])
        }
    }

    public static func b64(_ text: String) throws -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        var lookup = [Int](repeating: -1, count: 256)
        for (idx, byte) in alphabet.enumerated() {
            lookup[Int(byte)] = idx
        }
        var out = Data()
        out.reserveCapacity((text.utf8.count * 3) / 4)
        var value = 0
        var bits = 0
        for byte in text.utf8 {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
            if byte == 0x3D { break } // '='
            let digit = lookup[Int(byte)]
            if digit < 0 {
                throw NSError(domain: "PublicSourceImages", code: 3, userInfo: [NSLocalizedDescriptionKey: "无效 Base64"])
            }
            value = (value << 6) | digit
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return out
    }

    public static func match(_ text: String, _ expression: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) else {
            return ""
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges > 1,
              let g1 = Range(m.range(at: 1), in: text) else {
            return ""
        }
        return String(text[g1])
    }

    static func literal(_ text: String) throws -> String {
        try PublicRelaxedJSON.literal(text)
    }

    static func unpack(_ html: String) throws -> String {
        guard let startRegex = try? NSRegularExpression(pattern: #"\}\(\s*(?=['"])"#, options: []),
              let numRegex = try? NSRegularExpression(pattern: #"^\s*,\s*(\d+)\s*,\s*\d+\s*,\s*"#, options: []) else {
            return html
        }
        let fullRange = NSRange(html.startIndex..., in: html)
        let matches = startRegex.matches(in: html, options: [], range: fullRange)
        var out = html
        var count = 0
        for m in matches {
            if count >= 6 { break }
            count += 1
            guard let beginRange = Range(m.range, in: html) else { continue }
            let beginIdx = beginRange.upperBound
            let endIdx = try quotedEnd(html, from: beginIdx)
            let code = try literal(String(html[beginIdx..<endIdx]))

            let tailStr = String(html[endIdx...])
            let tailNSRange = NSRange(tailStr.startIndex..., in: tailStr)
            guard let numMatch = numRegex.firstMatch(in: tailStr, options: [.anchored], range: tailNSRange),
                  let radixRange = Range(numMatch.range(at: 1), in: tailStr),
                  let numFullRange = Range(numMatch.range(at: 0), in: tailStr),
                  let radixVal = Int(tailStr[radixRange]) else {
                continue
            }
            if radixVal < 2 || radixVal > 62 {
                throw NSError(domain: "PublicSourceImages", code: 4, userInfo: [NSLocalizedDescriptionKey: "字符串编码进制不支持"])
            }
            let dictBeginInTail = numFullRange.upperBound
            let dictEndInTail = try quotedEnd(tailStr, from: dictBeginInTail)
            let dictLiteral = try literal(String(tailStr[dictBeginInTail..<dictEndInTail]))
            let dict = dictLiteral.components(separatedBy: "|")
            var map: [String: String] = [:]
            map.reserveCapacity(dict.count)
            for (idx, word) in dict.enumerated() where !word.isEmpty {
                map[radix(idx, radixVal)] = word
            }
            let expanded = replaceWordTokens(in: code, with: map)
            out.append("\n")
            out.append(expanded)
        }
        return out
    }

    private static func quotedEnd(_ text: String, from start: String.Index) throws -> String.Index {
        guard start < text.endIndex, (text[start] == "\"" || text[start] == "'") else {
            throw NSError(domain: "PublicSourceImages", code: 5, userInfo: [NSLocalizedDescriptionKey: "缺少字符串"])
        }
        let quote = text[start]
        var escaped = false
        var idx = text.index(after: start)
        while idx < text.endIndex {
            let ch = text[idx]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == quote {
                return text.index(after: idx)
            }
            idx = text.index(after: idx)
        }
        throw NSError(domain: "PublicSourceImages", code: 6, userInfo: [NSLocalizedDescriptionKey: "字符串不完整"])
    }

    private static func radix(_ number: Int, _ base: Int) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var n = number
        var s = ""
        repeat {
            s.insert(chars[n % base], at: s.startIndex)
            n /= base
        } while n > 0
        return s
    }

    private static func replaceWordTokens(in code: String, with map: [String: String]) -> String {
        let bytes = Array(code.utf8)
        let n = bytes.count
        var out = Data()
        out.reserveCapacity(n + 256)
        var i = 0
        func isWordByte(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F
        }
        while i < n {
            if isWordByte(bytes[i]) {
                let start = i
                while i < n && isWordByte(bytes[i]) { i += 1 }
                let token = String(decoding: bytes[start..<i], as: UTF8.self)
                if let replacement = map[token] {
                    out.append(contentsOf: replacement.utf8)
                } else {
                    out.append(contentsOf: bytes[start..<i])
                }
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func extract(_ html: String, _ url: String, _ profile: PublicSourceProfile) throws -> [String] {
        var raw: [String] = []
        let decoder = profile.decoder
        do {
            if decoder == "aes" {
                let encrypted = try b64(match(html, #"params\s*=\s*['"]([^'"]+)"#))
                let plain = try decryptData(encrypted, key: Data("9S8$vJnU2ANeSRoF".utf8))
                guard let plainStr = String(data: plain, encoding: .utf8),
                      let obj = try PublicRelaxedJSON.parse(plainStr) as? [String: Any],
                      let values = obj["images"] as? [Any] else {
                    throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
                }
                for val in values {
                    if let s = val as? String {
                        raw.append(resolve("https://img1.baipiaoguai.org/", s))
                    }
                }
            } else if decoder == "xor" {
                let keys = [
                    "OC1iWGQ5aU4=", "OC1SWHlqcnk=", "OC1vWXZ3Vnk=", "OC00Wlk1N1U=", "OC1tYkpwVTc=",
                    "OC02TU0yRWk=", "OC01NFRpUXI=", "OC1QaDV4eDk=", "OC1iWWdlUFI=", "OC1aOUEzYlc="
                ]
                guard let cid = Int(match(html, #"\bcid\s*=\s*(\d+)"#)) else {
                    throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
                }
                let key = Array(try b64(keys[cid % 10]))
                var bytes = Array(try b64(match(html, #"\bDATA\s*=\s*['"]([^'"]+)"#)))
                guard !key.isEmpty else {
                    throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
                }
                for i in 0..<bytes.count {
                    bytes[i] ^= key[i % key.count]
                }
                let innerB64 = String(decoding: bytes, as: UTF8.self)
                let decodedData = try b64(innerB64)
                guard let jsonText = String(data: decodedData, encoding: .utf8),
                      let values = try PublicRelaxedJSON.parse(jsonText) as? [[String: Any]] else {
                    throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
                }
                for item in values {
                    if let u = item["url"] as? String {
                        raw.append(u)
                    }
                }
            } else if decoder == "base64" {
                let dataB64 = match(html, #"qTcms_S_m_murl_e\s*=\s*['"]([^'"]+)"#)
                let decoded = try b64(dataB64)
                let text = String(decoding: decoded, as: UTF8.self)
                raw.append(contentsOf: text.components(separatedBy: "$qingtiandy$"))
            } else if decoder == "numbered" {
                guard let count = Int(match(html, #"\bnum\s*=\s*(?:eval\(\s*)?['"]?(\d+)"#)) else {
                    throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
                }
                if count < 1 || count > 10000 {
                    throw NSError(domain: "PublicSourceImages", code: 8, userInfo: [NSLocalizedDescriptionKey: "章节页数超出范围"])
                }
                let prefix = match(html, #"\bpasd\s*=\s*['"]([^'"]+)"#)
                if !prefix.hasPrefix("http") {
                    throw NSError(domain: "PublicSourceImages", code: 9, userInfo: [NSLocalizedDescriptionKey: "图片目录缺失"])
                }
                let cleanPrefix = prefix.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
                for i in 1...count {
                    raw.append("\(cleanPrefix)/\(i).webp")
                }
            } else if decoder == "packed" {
                let body = try unpack(html)
                let array = match(body, #"\bnewImgs\s*=\s*(\[[\s\S]*?\])"#)
                if array.isEmpty {
                    throw NSError(domain: "PublicSourceImages", code: 10, userInfo: [NSLocalizedDescriptionKey: "章节图片数组缺失"])
                }
                guard let values = try PublicRelaxedJSON.parse(array) as? [Any] else {
                    throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
                }
                for v in values {
                    if let s = v as? String {
                        raw.append(s)
                    }
                }
            } else {
                let doc = PublicHTMLDocument.parse(html, baseUri: url)
                for img in doc.select(profile.reader) {
                    raw.append(imageAttribute(img))
                }
            }
        } catch let err as NSError where err.domain == "PublicSourceImages" {
            throw err
        } catch {
            throw NSError(domain: "PublicSourceImages", code: 7, userInfo: [NSLocalizedDescriptionKey: "章节图片解析失败"])
        }

        var unique: [String] = []
        var seen = Set<String>()
        let placeholderPattern = #"^.*/(?:loading|loadimg|blank|empty)\.(?:gif|png|svg|webp)(?:\?.*)?$"#
        let placeholderRegex = try? NSRegularExpression(pattern: placeholderPattern, options: [.caseInsensitive])
        for value in raw {
            guard !value.isEmpty, !value.hasPrefix("data:") else { continue }
            let range = NSRange(value.startIndex..., in: value)
            if placeholderRegex?.firstMatch(in: value, options: [], range: range) != nil { continue }
            let unescaped = value.replacingOccurrences(of: "\\/", with: "/")
            let u = resolve(url, unescaped)
            if (u.hasPrefix("http://") || u.hasPrefix("https://")), seen.insert(u).inserted {
                unique.append(u)
            }
        }
        return unique
    }

    public static func imageAttribute(_ img: PublicHTMLElement?) -> String {
        guard let img else { return "" }
        for key in ["data-page-image-url", "data-original", "data-src", "data-url", "src"] {
            let v = img.attr(key)
            if !v.isEmpty && !v.hasPrefix("data:") {
                return v
            }
        }
        return ""
    }

    public static func resolve(_ base: String, _ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let baseURL = parseLenientURL(base),
           let resolved = parseLenientURL(trimmed, relativeTo: baseURL) {
            return resolved.absoluteURL.absoluteString
        }
        return ""
    }

    static func parseLenientURL(_ string: String, relativeTo base: URL? = nil) -> URL? {
        if let u = URL(string: string, relativeTo: base) {
            return u
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#%/:@!$&'()*+,;=[]")
        if let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed),
           let u = URL(string: encoded, relativeTo: base) {
            return u
        }
        return nil
    }

    static func formURLEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    static func formURLDecode(_ text: String) -> String {
        let plusToSpace = text.replacingOccurrences(of: "+", with: " ")
        return plusToSpace.removingPercentEncoding ?? plusToSpace
    }
}
