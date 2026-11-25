import Foundation

public enum ManwaImageDecoder {
    public static let IMAGE_CDNS: [String] = [
        "https://182.16.62.30:8088",
        "https://141.193.154.190:8088",
        "https://141.193.154.22:8088",
        "https://tu.mwzu.cc",
        "https://38.246.114.12:8067"
    ]

    private static let domains: [String] = [
        "mwtuwu.cc", "mwzu.cc", "mhttu.cc", "mwtusi.cc", "manwauu.cc",
        "manwace.cc", "manwads.cc", "manwadz.cc", "manwaxu.cc",
        "manwapp.cc", "manwacn.cc", "manwahh.cc", "manwadh.cc", "manwadj.cc",
        "manwabb.cc", "manwayy.cc", "manwarr.cc", "manwazz.cc",
        "manwakk.cc", "manwann.cc", "manwaqq.cc", "mwmwff.cc", "mwmwbu.cc"
    ]

    private static let cdnIPs: [String] = [
        "182.16.62.30", "38.246.114.12", "141.193.154.190", "141.193.154.22"
    ]

    private static let cdnLock = NSLock()
    private static var internalPreferredCdn: String = IMAGE_CDNS[0]

    public static var preferredCdn: String {
        get {
            cdnLock.lock()
            defer { cdnLock.unlock() }
            return internalPreferredCdn
        }
        set {
            cdnLock.lock()
            internalPreferredCdn = newValue
            cdnLock.unlock()
        }
    }

    public static var imageHostCount: Int {
        IMAGE_CDNS.count
    }

    public static func usesImageHost(_ text: String) -> Bool {
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else {
            return false
        }
        if cdnIPs.contains(host) {
            return true
        }
        if domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        return url.path.hasPrefix("/en_images/")
    }

    public static func isOnlyImageDomain(_ host: String?) -> Bool {
        guard let lower = host?.lowercased(), !lower.isEmpty else { return false }
        return ["mwtuwu.cc", "mwzu.cc", "mhttu.cc", "mwtusi.cc", "manwauu.cc"].contains {
            lower == $0 || lower.hasSuffix("." + $0)
        }
    }

    public static func isDeadImageHost(_ host: String?) -> Bool {
        guard let lower = host?.lowercased(), !lower.isEmpty else { return false }
        return lower == "mwtuwu.cc" || lower.hasSuffix(".mwtuwu.cc")
            || lower == "mhttu.cc" || lower.hasSuffix(".mhttu.cc")
    }

    public static func markImageHostSuccess(_ imageUrl: String) {
        guard let parsed = URL(string: imageUrl),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host?.lowercased(),
              !isDeadImageHost(host) else {
            return
        }
        let origin = "\(scheme)://\(host)\(parsed.port.map { ":\($0)" } ?? "")"
        if let matched = IMAGE_CDNS.first(where: { $0.caseInsensitiveCompare(origin) == .orderedSame }) {
            preferredCdn = matched
        }
    }

    public static func resolveImageUrl(_ imageUrl: String, attempt: Int) -> String {
        guard !imageUrl.isEmpty,
              let parsed = URL(string: imageUrl),
              let scheme = parsed.scheme?.lowercased(),
              let host = parsed.host?.lowercased() else {
            return imageUrl
        }
        if host == "127.0.0.1" { return imageUrl }
        let file = parsed.path + (parsed.query.map { "?\($0)" } ?? "")
        guard file.hasPrefix("/en_images/") else { return imageUrl }
        let originalOrigin = "\(scheme)://\(host)\(parsed.port.map { ":\($0)" } ?? "")"
        let currentPreferred = preferredCdn
        if attempt <= 0 {
            return isDeadImageHost(host) ? (currentPreferred + file) : imageUrl
        }
        let currentFirst = isDeadImageHost(host) ? currentPreferred : originalOrigin
        let candidates = IMAGE_CDNS.filter { $0.caseInsensitiveCompare(currentFirst) != .orderedSame }
        guard !candidates.isEmpty else { return imageUrl }
        let chosen = candidates[(attempt - 1) % candidates.count]
        preferredCdn = chosen
        return chosen + file
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
