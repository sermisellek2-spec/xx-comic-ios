import Foundation

public enum ManwaImageDecoder {
    public static func usesImageHost(_ text: String) -> Bool {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return false }
        return ["mwtuwu.cc", "mwzu.cc", "mhttu.cc", "manwace.cc"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// This default is the site's published image-format key, not an account credential.
    public static func decode(_ data: Data, publicKey: String = "0B6666A0-BB59-1381-B746-a0E4C9AC") throws -> Data {
        try Task.checkCancellation()
        guard data.count >= 16 else { throw SourceAES.DecodeError.invalidInput }
        if isImage(data) { return data }
        let key = Data(publicKey.utf8)
        guard key.count == 32 else { throw SourceAES.DecodeError.invalidInput }
        let decoded = try SourceAES.decrypt(Data(data.dropFirst(16)), key: key, iv: Data(data.prefix(16)))
        guard decoded.count >= 16, isImage(decoded) else { throw SourceAES.DecodeError.decryptionFailed }
        return decoded
    }

    private static func isImage(_ data: Data) -> Bool {
        data.starts(with: [0xff, 0xd8, 0xff]) || data.starts(with: [0x89, 0x50, 0x4e, 0x47]) || data.starts(with: "GIF8".utf8) ||
            (data.starts(with: "RIFF".utf8) && data.dropFirst(8).starts(with: "WEBP".utf8))
    }
}
