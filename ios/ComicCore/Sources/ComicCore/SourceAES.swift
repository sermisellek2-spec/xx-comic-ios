import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The sites use AES-CBC with PKCS7 padding (Java calls this PKCS5Padding),
/// while Rule Engine API v3 also supports ECB/CTR and NoPadding/PKCS7 modes.
enum SourceAES {
    static func decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
        try Task.checkCancellation()
        guard [16, 24, 32].contains(key.count), iv.count == 16,
              !ciphertext.isEmpty, ciphertext.count.isMultiple(of: 16),
              !ciphertext.allSatisfy({ $0 == 0 }) else { throw DecodeError.invalidInput }
        let out = try cbcDecrypt(ciphertext, key: key, iv: iv, pkcs7: true)
        try Task.checkCancellation()
        return out
    }

    static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw DecodeError.invalidInput }
        return try cbcEncrypt(plaintext, key: key, iv: iv, pkcs7: true)
    }

    static func cbcEncrypt(_ plaintext: Data, key: Data, iv: Data, pkcs7: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw DecodeError.invalidInput }
        let input: Data
        if pkcs7 {
            input = applyPkcs7(plaintext)
        } else {
            guard plaintext.count.isMultiple(of: 16) else { throw DecodeError.invalidInput }
            if plaintext.isEmpty { return Data() }
            input = plaintext
        }
        #if canImport(CommonCrypto)
        var output = Data(count: input.count)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(0),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                bytes.baseAddress, input.count, out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.decryptionFailed }
        output.count = written
        return output
        #else
        let cipher = try PureAES(key: Array(key))
        let inBytes = Array(input)
        var outBytes = [UInt8](repeating: 0, count: inBytes.count)
        var prev = Array(iv)
        var offset = 0
        while offset < inBytes.count {
            var block = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 {
                block[i] = inBytes[offset + i] ^ prev[i]
            }
            let enc = cipher.encryptBlock(block)
            for i in 0..<16 {
                outBytes[offset + i] = enc[i]
            }
            prev = enc
            offset += 16
        }
        return Data(outBytes)
        #endif
    }

    static func cbcDecrypt(_ ciphertext: Data, key: Data, iv: Data, pkcs7: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw DecodeError.invalidInput }
        if !pkcs7 && ciphertext.isEmpty { return Data() }
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: 16) else { throw DecodeError.invalidInput }
        #if canImport(CommonCrypto)
        var output = Data(count: ciphertext.count)
        let capacity = output.count
        var written = 0
        let options = pkcs7 ? CCOptions(kCCOptionPKCS7Padding) : CCOptions(0)
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                bytes.baseAddress, ciphertext.count, out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.decryptionFailed }
        output.count = written
        return output
        #else
        let cipher = try PureAES(key: Array(key))
        let inBytes = Array(ciphertext)
        var outBytes = [UInt8](repeating: 0, count: inBytes.count)
        var prev = Array(iv)
        var offset = 0
        while offset < inBytes.count {
            let cBlock = Array(inBytes[offset..<(offset + 16)])
            let dec = cipher.decryptBlock(cBlock)
            for i in 0..<16 {
                outBytes[offset + i] = dec[i] ^ prev[i]
            }
            prev = cBlock
            offset += 16
        }
        let raw = Data(outBytes)
        return pkcs7 ? try stripPkcs7(raw) : raw
        #endif
    }

    static func ecbEncrypt(_ plaintext: Data, key: Data, pkcs7: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count) else { throw DecodeError.invalidInput }
        let input: Data
        if pkcs7 {
            input = applyPkcs7(plaintext)
        } else {
            guard plaintext.count.isMultiple(of: 16) else { throw DecodeError.invalidInput }
            if plaintext.isEmpty { return Data() }
            input = plaintext
        }
        return try ecbRawEncrypt(input, key: key)
    }

    static func ecbDecrypt(_ ciphertext: Data, key: Data, pkcs7: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count) else { throw DecodeError.invalidInput }
        if !pkcs7 && ciphertext.isEmpty { return Data() }
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: 16) else { throw DecodeError.invalidInput }
        #if canImport(CommonCrypto)
        var output = Data(count: ciphertext.count)
        let capacity = output.count
        var written = 0
        let options = pkcs7 ? CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode) : CCOptions(kCCOptionECBMode)
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                            keyBytes.baseAddress, key.count, nil,
                            bytes.baseAddress, ciphertext.count, out.baseAddress, capacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.decryptionFailed }
        output.count = written
        return output
        #else
        let cipher = try PureAES(key: Array(key))
        let inBytes = Array(ciphertext)
        var outBytes = [UInt8](repeating: 0, count: inBytes.count)
        var offset = 0
        while offset < inBytes.count {
            let dec = cipher.decryptBlock(Array(inBytes[offset..<(offset + 16)]))
            for i in 0..<16 {
                outBytes[offset + i] = dec[i]
            }
            offset += 16
        }
        let raw = Data(outBytes)
        return pkcs7 ? try stripPkcs7(raw) : raw
        #endif
    }

    /// AES/CTR/NoPadding (big-endian 128-bit counter increment, matching Java Cipher "AES/CTR/NoPadding").
    static func ctrCrypt(_ input: Data, key: Data, iv: Data) throws -> Data {
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw DecodeError.invalidInput }
        if input.isEmpty { return Data() }
        let blockCount = (input.count + 15) / 16
        var counters = [UInt8](repeating: 0, count: blockCount * 16)
        var counter = Array(iv)
        for b in 0..<blockCount {
            let base = b * 16
            for i in 0..<16 {
                counters[base + i] = counter[i]
            }
            // Increment 128-bit big-endian counter
            for i in stride(from: 15, through: 0, by: -1) {
                counter[i] = counter[i] &+ 1
                if counter[i] != 0 { break }
            }
        }
        let keystream = try ecbRawEncrypt(Data(counters), key: key)
        var out = [UInt8](repeating: 0, count: input.count)
        input.withUnsafeBytes { inRaw in
            keystream.withUnsafeBytes { ksRaw in
                let inPtr = inRaw.bindMemory(to: UInt8.self)
                let ksPtr = ksRaw.bindMemory(to: UInt8.self)
                for i in 0..<input.count {
                    out[i] = inPtr[i] ^ ksPtr[i]
                }
            }
        }
        return Data(out)
    }

    static func hmacSha1(data: Data, key: Data) -> Data {
        #if canImport(CryptoKit)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
        #else
        return pureHmac(data: data, key: key, blockSize: 64, hash: pureSha1)
        #endif
    }

    static func hmacSha256(data: Data, key: Data) -> Data {
        #if canImport(CryptoKit)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
        #else
        return pureHmac(data: data, key: key, blockSize: 64, hash: { d in
            let hex = DownloadModels.sha256Hex(d)
            var out = Data()
            out.reserveCapacity(32)
            var idx = hex.startIndex
            while idx < hex.endIndex {
                let next = hex.index(idx, offsetBy: 2)
                out.append(UInt8(hex[idx..<next], radix: 16) ?? 0)
                idx = next
            }
            return out
        })
        #endif
    }

    private static func ecbRawEncrypt(_ input: Data, key: Data) throws -> Data {
        #if canImport(CommonCrypto)
        var output = Data(count: input.count)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            keyBytes.baseAddress, key.count, nil,
                            bytes.baseAddress, input.count, out.baseAddress, capacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.decryptionFailed }
        output.count = written
        return output
        #else
        let cipher = try PureAES(key: Array(key))
        let inBytes = Array(input)
        var outBytes = [UInt8](repeating: 0, count: inBytes.count)
        var offset = 0
        while offset < inBytes.count {
            let enc = cipher.encryptBlock(Array(inBytes[offset..<(offset + 16)]))
            for i in 0..<16 {
                outBytes[offset + i] = enc[i]
            }
            offset += 16
        }
        return Data(outBytes)
        #endif
    }

    private static func applyPkcs7(_ data: Data) -> Data {
        let padLen = 16 - (data.count % 16)
        var padded = data
        padded.append(contentsOf: repeatElement(UInt8(padLen), count: padLen))
        return padded
    }

    private static func stripPkcs7(_ padded: Data) throws -> Data {
        guard let padding = padded.last, (1...16).contains(Int(padding)),
              padded.count >= Int(padding),
              padded.suffix(Int(padding)).allSatisfy({ $0 == padding }) else {
            throw DecodeError.decryptionFailed
        }
        return Data(padded.dropLast(Int(padding)))
    }

    #if !canImport(CryptoKit)
    private static func pureHmac(data: Data, key: Data, blockSize: Int, hash: (Data) -> Data) -> Data {
        let normalizedKey: [UInt8]
        if key.count > blockSize {
            normalizedKey = Array(hash(key))
        } else {
            normalizedKey = Array(key)
        }
        var kPad = [UInt8](repeating: 0, count: blockSize)
        for i in 0..<normalizedKey.count {
            kPad[i] = normalizedKey[i]
        }
        var ipad = Data(kPad.map { $0 ^ 0x36 })
        var opad = Data(kPad.map { $0 ^ 0x5c })
        ipad.append(data)
        let inner = hash(ipad)
        opad.append(inner)
        return hash(opad)
    }

    private static func pureSha1(_ data: Data) -> Data {
        var msg = Array(data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while (msg.count % 64) != 56 {
            msg.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            msg.append(UInt8((bitLen >> UInt64(shift)) & 0xff))
        }
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        var w = [UInt32](repeating: 0, count: 80)
        var chunkOffset = 0
        while chunkOffset < msg.count {
            for i in 0..<16 {
                let j = chunkOffset + i * 4
                w[i] = (UInt32(msg[j]) << 24) | (UInt32(msg[j + 1]) << 16) | (UInt32(msg[j + 2]) << 8) | UInt32(msg[j + 3])
            }
            for i in 16..<80 {
                let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                if i < 20 {
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                } else if i < 40 {
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                } else if i < 60 {
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                } else {
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let rotA = (a << 5) | (a >> 27)
                let temp = rotA &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            chunkOffset += 64
        }
        var out = Data()
        out.reserveCapacity(20)
        for word in [h0, h1, h2, h3, h4] {
            out.append(UInt8((word >> 24) & 0xff))
            out.append(UInt8((word >> 16) & 0xff))
            out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8(word & 0xff))
        }
        return out
    }
    #endif

    enum DecodeError: Error, Equatable, LocalizedError {
        case invalidInput, decryptionFailed, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidInput: return "站源加密数据格式无效。"
            case .decryptionFailed: return "站源数据解码失败，请刷新后重试。"
            case .unavailable: return "当前平台不支持此站源的数据解码。"
            }
        }
    }
}

#if !canImport(CommonCrypto)
/// Pure-Swift FIPS-197 AES-128/192/256 block cipher for non-Apple test environments.
private struct PureAES {
    private static let sbox: [UInt8] = [
        0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
        0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
        0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
        0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
        0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
        0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
        0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
        0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
        0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
        0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
        0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
        0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
        0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
        0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
        0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
        0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
    ]

    private static let invSbox: [UInt8] = {
        var inv = [UInt8](repeating: 0, count: 256)
        for (idx, val) in sbox.enumerated() {
            inv[Int(val)] = UInt8(idx)
        }
        return inv
    }()

    private static let rcon: [UInt8] = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]

    private let nr: Int
    private let roundKeys: [UInt8]

    init(key: [UInt8]) throws {
        let nk: Int
        switch key.count {
        case 16: nk = 4; nr = 10
        case 24: nk = 6; nr = 12
        case 32: nk = 8; nr = 14
        default: throw SourceAES.DecodeError.invalidInput
        }
        let totalWords = 4 * (nr + 1)
        var w = [UInt8](repeating: 0, count: totalWords * 4)
        for i in 0..<key.count { w[i] = key[i] }
        var temp = [UInt8](repeating: 0, count: 4)
        for i in nk..<totalWords {
            let prev = (i - 1) * 4
            temp[0] = w[prev]; temp[1] = w[prev + 1]; temp[2] = w[prev + 2]; temp[3] = w[prev + 3]
            if i % nk == 0 {
                let t = temp[0]
                temp[0] = Self.sbox[Int(temp[1])] ^ Self.rcon[i / nk]
                temp[1] = Self.sbox[Int(temp[2])]
                temp[2] = Self.sbox[Int(temp[3])]
                temp[3] = Self.sbox[Int(t)]
            } else if nk > 6 && i % nk == 4 {
                for j in 0..<4 { temp[j] = Self.sbox[Int(temp[j])] }
            }
            let back = (i - nk) * 4
            let dst = i * 4
            for j in 0..<4 { w[dst + j] = w[back + j] ^ temp[j] }
        }
        self.roundKeys = w
    }

    private static func xtime(_ x: UInt8) -> UInt8 {
        (x << 1) ^ (((x >> 7) & 1) * 0x1b)
    }

    private static func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var aa = a, bb = b, p: UInt8 = 0
        for _ in 0..<8 {
            if (bb & 1) != 0 { p ^= aa }
            let hi = aa & 0x80
            aa <<= 1
            if hi != 0 { aa ^= 0x1b }
            bb >>= 1
        }
        return p
    }

    func encryptBlock(_ input: [UInt8]) -> [UInt8] {
        var s = input
        addRoundKey(&s, round: 0)
        for round in 1..<nr {
            for i in 0..<16 { s[i] = Self.sbox[Int(s[i])] }
            shiftRows(&s)
            mixColumns(&s)
            addRoundKey(&s, round: round)
        }
        for i in 0..<16 { s[i] = Self.sbox[Int(s[i])] }
        shiftRows(&s)
        addRoundKey(&s, round: nr)
        return s
    }

    func decryptBlock(_ input: [UInt8]) -> [UInt8] {
        var s = input
        addRoundKey(&s, round: nr)
        for round in stride(from: nr - 1, through: 1, by: -1) {
            invShiftRows(&s)
            for i in 0..<16 { s[i] = Self.invSbox[Int(s[i])] }
            addRoundKey(&s, round: round)
            invMixColumns(&s)
        }
        invShiftRows(&s)
        for i in 0..<16 { s[i] = Self.invSbox[Int(s[i])] }
        addRoundKey(&s, round: 0)
        return s
    }

    private func addRoundKey(_ s: inout [UInt8], round: Int) {
        let base = round * 16
        for i in 0..<16 { s[i] ^= roundKeys[base + i] }
    }

    private func shiftRows(_ s: inout [UInt8]) {
        let t1 = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t1
        let t2 = s[2]; let t6 = s[6]; s[2] = s[10]; s[6] = s[14]; s[10] = t2; s[14] = t6
        let t3 = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t3
    }

    private func invShiftRows(_ s: inout [UInt8]) {
        let t1 = s[13]; s[13] = s[9]; s[9] = s[5]; s[5] = s[1]; s[1] = t1
        let t2 = s[2]; let t6 = s[6]; s[2] = s[10]; s[6] = s[14]; s[10] = t2; s[14] = t6
        let t3 = s[3]; s[3] = s[7]; s[7] = s[11]; s[11] = s[15]; s[15] = t3
    }

    private func mixColumns(_ s: inout [UInt8]) {
        for c in 0..<4 {
            let i = c * 4
            let a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3]
            let t = a0 ^ a1 ^ a2 ^ a3
            s[i]     ^= t ^ Self.xtime(a0 ^ a1)
            s[i + 1] ^= t ^ Self.xtime(a1 ^ a2)
            s[i + 2] ^= t ^ Self.xtime(a2 ^ a3)
            s[i + 3] ^= t ^ Self.xtime(a3 ^ a0)
        }
    }

    private func invMixColumns(_ s: inout [UInt8]) {
        for c in 0..<4 {
            let i = c * 4
            let a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3]
            s[i]     = Self.gmul(a0, 0x0e) ^ Self.gmul(a1, 0x0b) ^ Self.gmul(a2, 0x0d) ^ Self.gmul(a3, 0x09)
            s[i + 1] = Self.gmul(a0, 0x09) ^ Self.gmul(a1, 0x0e) ^ Self.gmul(a2, 0x0b) ^ Self.gmul(a3, 0x0d)
            s[i + 2] = Self.gmul(a0, 0x0d) ^ Self.gmul(a1, 0x09) ^ Self.gmul(a2, 0x0e) ^ Self.gmul(a3, 0x0b)
            s[i + 3] = Self.gmul(a0, 0x0b) ^ Self.gmul(a1, 0x0d) ^ Self.gmul(a2, 0x09) ^ Self.gmul(a3, 0x0e)
        }
    }
}
#endif
