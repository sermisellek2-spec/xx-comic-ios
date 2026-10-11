import Foundation

/// Browser distribution is the iOS equivalent of Android's in-app APK update.
public enum IOSUpdatePolicy {
    public static let releasesURL = URL(string: "https://github.com/sermisellek2-spec/xx-comic-ios/releases")!
    public static let installationHint = "将在浏览器中打开 iOS 发布页。下载 IPA 后，请使用现有签名工具安装更新。"

    public static func browserURL(for release: AppRelease) -> URL {
        guard let value = release.downloadUrl, let url = URL(string: value),
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil else { return releasesURL }
        let path = url.path
        let prefix = releasesURL.path + "/"
        guard path.hasPrefix(prefix) else { return releasesURL }
        if path.hasPrefix(prefix + "download/"), url.pathExtension.lowercased() == "ipa" {
            return url
        }
        if path.hasPrefix(prefix + "tag/"), !path.dropFirst((prefix + "tag/").count).isEmpty {
            return url
        }
        return releasesURL
    }
}
