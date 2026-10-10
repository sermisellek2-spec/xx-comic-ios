import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum DownloadState: String, Codable, Sendable {
    case queued = "QUEUED"
    case resolving = "RESOLVING"
    case downloading = "DOWNLOADING"
    case verifying = "VERIFYING"
    case completed = "COMPLETED"
    case pausedUser = "PAUSED_USER"
    case waitingNetwork = "WAITING_NETWORK"
    case waitingVerification = "WAITING_VERIFICATION"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case deleting = "DELETING"
}

public struct DownloadTask: Codable, Equatable, Sendable {
    public var id: String
    public var bookId: String
    public var sourceId: String
    public var comicId: String
    public var chapterId: String
    public var title: String
    public var url: String
    public var error: String
    public var order: Int
    public var failures: Int
    public var totalPages: Int
    public var donePages: Int
    public var generation: Int64
    public var bytes: Int64
    public var nextAttempt: Int64
    public var state: DownloadState

    // Stage 6 file task fields
    public var isFileTask: Bool
    public var fileId: String?
    public var revision: String
    public var expectedFormat: String
    public var sha256: String?
    public var expiresAt: Int64
    public var expectedBytes: Int64
    public var refreshCount: Int

    public init(id: String = "",
                bookId: String = "",
                sourceId: String = "",
                comicId: String = "",
                chapterId: String = "",
                title: String = "",
                url: String = "",
                error: String = "",
                order: Int = 0,
                failures: Int = 0,
                totalPages: Int = 0,
                donePages: Int = 0,
                generation: Int64 = 0,
                bytes: Int64 = 0,
                nextAttempt: Int64 = 0,
                state: DownloadState = .queued,
                isFileTask: Bool = false,
                fileId: String? = nil,
                revision: String = "",
                expectedFormat: String = "",
                sha256: String? = nil,
                expiresAt: Int64 = 0,
                expectedBytes: Int64 = -1,
                refreshCount: Int = 0) {
        self.id = id
        self.bookId = bookId
        self.sourceId = sourceId
        self.comicId = comicId
        self.chapterId = chapterId
        self.title = title
        self.url = url
        self.error = error
        self.order = order
        self.failures = failures
        self.totalPages = totalPages
        self.donePages = donePages
        self.generation = generation
        self.bytes = bytes
        self.nextAttempt = nextAttempt
        self.state = state
        self.isFileTask = isFileTask
        self.fileId = fileId
        self.revision = revision
        self.expectedFormat = expectedFormat
        self.sha256 = sha256
        self.expiresAt = expiresAt
        self.expectedBytes = expectedBytes
        self.refreshCount = refreshCount
    }
}

public struct DownloadPage: Codable, Equatable, Sendable {
    public let index: Int
    public let url: String
    public let path: String
    public let hash: String
    public let bytes: Int64

    public init(index: Int, url: String, path: String, hash: String, bytes: Int64) {
        self.index = index
        self.url = url
        self.path = path
        self.hash = hash
        self.bytes = bytes
    }
}

public enum DownloadError: LocalizedError, Equatable {
    case invalidIdentity
    case digestFailed
    case noSpace
    case taskCancelled
    case invalidChapter
    case corruptedData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentity: return "缺少作品或章节身份"
        case .digestFailed: return "哈希计算失败"
        case .noSpace: return "空间不足，请清理后继续"
        case .taskCancelled: return "下载任务已取消"
        case .invalidChapter: return "章节没有可下载的图片"
        case .corruptedData(let msg): return msg
        }
    }
}

public enum DownloadModels {
    public static func active(_ state: DownloadState) -> Bool {
        state == .resolving || state == .downloading || state == .verifying
    }

    public static func key(_ components: String...) throws -> String {
        try key(components)
    }

    public static func key(_ components: [String]) throws -> String {
        for part in components {
            guard !part.isEmpty else { throw DownloadError.invalidIdentity }
        }
        var data = Data()
        for part in components {
            let partBytes = Array(part.utf8)
            let lenAscii = Array(String(partBytes.count).utf8)
            data.append(contentsOf: lenAscii)
            data.append(contentsOf: [UInt8(ascii: ":")])
            data.append(contentsOf: partBytes)
        }
        return sha256Hex(data)
    }

    public static func bookId(source: String, comic: String) throws -> String {
        "local_dl_" + (try key(source, comic))
    }

    public static func fileTaskId(source: String, comic: String, file: String) throws -> String {
        try key("file", source, comic, file)
    }

    public static func fileBookId(source: String, comic: String, file: String) throws -> String {
        "local_file_" + (try fileTaskId(source: source, comic: comic, file: file))
    }

    public static func imageIdentity(_ url: String) -> String {
        if !PublicSourceImages.sourceId(url).isEmpty {
            return PublicSourceImages.cacheIdentity(url)
        }
        let stable = ZaimanhuaComicSource.imageCacheIdentity(url)
        if stable != url { return stable }
        let base = url.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
        if let regex = try? NSRegularExpression(pattern: #"[?&]scramble_id=(\d+)"#),
           let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let range = Range(match.range(at: 1), in: url) {
            return base + "?scramble_id=" + String(url[range])
        }
        return base
    }

    public static func sameImage(_ a: String, _ b: String) -> Bool {
        imageIdentity(a) == imageIdentity(b)
    }

    public static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return PureSwiftSHA256.digestHex(data)
        #endif
    }
}

/// Pure Swift fallback implementation of FIPS 180-4 SHA-256
fileprivate enum PureSwiftSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func digestHex(_ data: Data) -> String {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]

        var message = Array(data)
        let bitLength = UInt64(data.count) * 8
        message.append(0x80)
        while (message.count * 8) % 512 != 448 {
            message.append(0x00)
        }
        for i in (0..<8).reversed() {
            message.append(UInt8((bitLength >> (i * 8)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = (UInt32(message[offset]) << 24) |
                       (UInt32(message[offset + 1]) << 16) |
                       (UInt32(message[offset + 2]) << 8) |
                       UInt32(message[offset + 3])
            }
            for i in 16..<64 {
                let s0 = (w[i - 15] >> 7 | w[i - 15] << 25) ^
                         (w[i - 15] >> 18 | w[i - 15] << 14) ^
                         (w[i - 15] >> 3)
                let s1 = (w[i - 2] >> 17 | w[i - 2] << 15) ^
                         (w[i - 2] >> 19 | w[i - 2] << 13) ^
                         (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hVal = h[7]

            for i in 0..<64 {
                let s1 = (e >> 6 | e << 26) ^ (e >> 11 | e << 21) ^ (e >> 25 | e << 7)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hVal &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = (a >> 2 | a << 30) ^ (a >> 13 | a << 19) ^ (a >> 22 | a << 10)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                hVal = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
            h[5] = h[5] &+ f
            h[6] = h[6] &+ g
            h[7] = h[7] &+ hVal
        }

        return h.map { String(format: "%08x", $0) }.joined()
    }
}
