import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum JmImageTransform {
    public struct Slice: Equatable, Sendable {
        public let sourceY: Int
        public let targetY: Int
        public let height: Int
    }
    public static func slices(aid: Int64, scrambleID: Int64, fileName: String) throws -> Int {
        try Task.checkCancellation()
        guard aid >= 0, scrambleID >= 0, aid >= scrambleID else { return 0 }
        if aid < 268_850 { return 10 }
        let stem: String
        if let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex { stem = String(fileName[..<dot]) }
        else { stem = fileName }
        let last = try digestLastByte(Data((String(aid) + stem).utf8)) & 15
        let character = Int(last < 10 ? 48 + last : 97 + last - 10)
        try Task.checkCancellation()
        return character % (aid >= 421_926 ? 8 : 10) * 2 + 2
    }

    public static func slices(imageURL: String) throws -> Int {
        try Task.checkCancellation()
        guard let url = URLComponents(string: imageURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), host.hasPrefix("cdn-msp"), host.hasSuffix(".18comic.vip"),
              url.port == nil, url.user == nil, url.password == nil else { return 0 }
        let parts = url.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "media", parts[2] == "photos",
              !parts[3].isEmpty, parts[3].utf8.allSatisfy({ (48...57).contains($0) }), let aid = Int64(parts[3]),
              !parts[4].isEmpty,
              let raw = url.percentEncodedQuery?.split(separator: "&").first(where: { $0.hasPrefix("scramble_id=") })?.dropFirst(12),
              !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let scramble = Int64(raw) else { return 0 }
        return try slices(aid: aid, scrambleID: scramble, fileName: String(parts[4]))
    }

    public static func bounds(height: Int, slices: Int) -> [Slice] {
        guard slices > 1, height >= slices else { return [] }
        let size = height / slices, remainder = height % slices
        var targetY = 0
        return (0..<slices).map { index in
            let count = size + (index == 0 ? remainder : 0)
            defer { targetY += count }
            return Slice(sourceY: height - targetY - count, targetY: targetY, height: count)
        }
    }

    private static func digestLastByte(_ data: Data) throws -> UInt8 {
#if canImport(CryptoKit)
        // MD5 is part of the published image layout, not authentication.
        return Array(Insecure.MD5.hash(data: data)).last!
#elseif os(Linux)
        // Existing Docker toolchain only. Apple uses CryptoKit, never a subprocess.
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["dgst", "-md5", "-binary"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        try input.fileHandleForWriting.write(contentsOf: data)
        try input.fileHandleForWriting.close()
        let digest = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0, digest.count == 16, let last = digest.last else { throw TransformError.decodeFailed }
        return last
#else
        throw TransformError.decodeFailed
#endif
    }

    public enum TransformError: Error, LocalizedError {
        case decodeFailed
        public var errorDescription: String? { "正文图片还原失败，请重试。" }
    }
}
