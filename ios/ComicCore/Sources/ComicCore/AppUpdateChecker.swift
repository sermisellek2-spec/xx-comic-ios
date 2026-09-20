import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AppRelease: Codable, Equatable, Sendable {
    public let versionName: String
    public let versionCode: Int
    public let size: Int64
    public let sha256: String
    public let updateMode: String
    public let releaseNotes: String
    public let downloadUrl: String?

    public init(versionName: String,
                versionCode: Int,
                size: Int64 = 0,
                sha256: String = "",
                updateMode: String = "soft",
                releaseNotes: String = "",
                downloadUrl: String? = nil) {
        self.versionName = versionName
        self.versionCode = versionCode
        self.size = size
        self.sha256 = sha256
        self.updateMode = updateMode
        self.releaseNotes = releaseNotes
        self.downloadUrl = downloadUrl
    }

    public func hasNewVersion(currentVersionCode: Int) -> Bool {
        return versionCode > currentVersionCode
    }

    public static func parse(from jsonString: String) throws -> AppRelease {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "AppRelease", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的数据"])
        }
        let decoder = JSONDecoder()
        return try decoder.decode(AppRelease.self, from: data)
    }
}

public final class AppUpdateChecker: @unchecked Sendable {
    public static let shared = AppUpdateChecker()
    public static let defaultMetadataURL = "https://weifeng.cloud/xx-comic/releases/ios-release.json"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchRelease(url: URL = URL(string: defaultMetadataURL)!) async throws -> AppRelease {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        #if canImport(FoundationNetworking)
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error { return continuation.resume(throwing: error) }
                guard let data, let response else {
                    return continuation.resume(throwing: URLError(.badServerResponse))
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
        #else
        let (data, response) = try await session.data(for: request)
        #endif

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AppRelease.self, from: data)
    }
}
