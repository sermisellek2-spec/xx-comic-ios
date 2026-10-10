import Foundation

/// The site's JPEG payload is prefixed with an 80-byte metadata header (1:1 with Android XinmanhuaImageDecoder.java).
public enum XinmanhuaImageDecoder {
    private static let magic = Array("http://www.xinmanhua.net".utf8)

    public static func usesImageHost(_ url: String) -> Bool {
        let base = url.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: base), let host = parsed.host else { return false }
        return host.caseInsensitiveCompare("works.xinmanhua.net") == .orderedSame
    }

    public static func decode(_ data: Data) throws -> Data {
        guard data.count >= magic.count, data.starts(with: magic) else {
            return data
        }
        let s = data.startIndex
        guard data.count >= 83,
              data[s + 80] == 0xff,
              data[s + 81] == 0xd8,
              data[s + 82] == 0xff else {
            throw NSError(domain: "XinmanhuaImageDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "新漫画图片文件头损坏"])
        }
        return Data(data.dropFirst(80))
    }
}
