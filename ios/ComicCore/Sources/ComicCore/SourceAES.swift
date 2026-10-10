import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// The sites use AES-CBC with PKCS7 padding (Java calls this PKCS5Padding).
enum SourceAES {
    static func decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
        try Task.checkCancellation()
        guard [16, 24, 32].contains(key.count), iv.count == 16,
              !ciphertext.isEmpty, ciphertext.count.isMultiple(of: 16),
              !ciphertext.allSatisfy({ $0 == 0 }) else { throw DecodeError.invalidInput }
#if canImport(CommonCrypto)
        var output = Data(count: ciphertext.count)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                bytes.baseAddress, ciphertext.count, out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.decryptionFailed }
        output.count = written
#elseif os(Linux)
        // Linux is the Windows/Docker test harness. iOS never executes a process.
        // File-backed IO avoids a full pipe blocking large image payloads.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xxcomic-aes-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input"), result = directory.appendingPathComponent("output")
        try ciphertext.write(to: input)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["enc", "-d", "-aes-\(key.count * 8)-cbc", "-nopad", "-K", key.map { String(format: "%02x", $0) }.joined(),
                             "-iv", iv.map { String(format: "%02x", $0) }.joined(), "-in", input.path, "-out", result.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw DecodeError.decryptionFailed }
        let padded = try Data(contentsOf: result)
        guard let padding = padded.last, (1...16).contains(Int(padding)),
              padded.count >= Int(padding),
              padded.suffix(Int(padding)).allSatisfy({ $0 == padding }) else {
            throw DecodeError.decryptionFailed
        }
        let output = Data(padded.dropLast(Int(padding)))
#else
        throw DecodeError.unavailable
#endif
#if canImport(CommonCrypto) || os(Linux)
        try Task.checkCancellation()
        return output
#endif
    }

    static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw DecodeError.invalidInput }
#if canImport(CommonCrypto)
        let capacity = plaintext.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            plaintext.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                bytes.baseAddress, plaintext.count, out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.decryptionFailed }
        output.count = written
        return output
#elseif os(Linux)
        let padLen = 16 - (plaintext.count % 16)
        var padded = plaintext
        padded.append(contentsOf: repeatElement(UInt8(padLen), count: padLen))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xxcomic-aes-enc-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input"), result = directory.appendingPathComponent("output")
        try padded.write(to: input)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["enc", "-e", "-aes-\(key.count * 8)-cbc", "-nopad", "-K", key.map { String(format: "%02x", $0) }.joined(),
                             "-iv", iv.map { String(format: "%02x", $0) }.joined(), "-in", input.path, "-out", result.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DecodeError.decryptionFailed }
        return try Data(contentsOf: result)
#else
        throw DecodeError.unavailable
#endif
    }

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
