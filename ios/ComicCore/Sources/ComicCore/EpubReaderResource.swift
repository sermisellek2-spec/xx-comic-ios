import Foundation

public enum EpubReaderResource {
    public static func url(bookID: String, path: String, fragment: String? = nil) throws -> URL {
        guard let id = UUID(uuidString: bookID), try EpubArchive.normalized(path) == path else {
            throw LocalLibraryError.invalidBook
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+")
        var parts = URLComponents()
        parts.scheme = "xxcomic-book"
        parts.host = id.uuidString.lowercased()
        parts.percentEncodedPath = "/" + path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "/")
        parts.fragment = fragment
        guard let url = parts.url else { throw LocalLibraryError.invalidBook }
        return url
    }

    public static func path(from url: URL, bookID: String) throws -> String {
        guard let id = UUID(uuidString: bookID),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "xxcomic-book", parts.percentEncodedHost == id.uuidString.lowercased(),
              url.absoluteString.hasPrefix("xxcomic-book://\(id.uuidString.lowercased())/"),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil,
              parts.percentEncodedPath.hasPrefix("/") else { throw LocalLibraryError.invalidBook }
        // URLComponents normalizes an empty port ("host:/path") to nil. Keep
        // the authority strict so that an explicit, malformed port is rejected.
        guard !url.absoluteString.contains("://\(id.uuidString.lowercased()):/") else {
            throw LocalLibraryError.invalidBook
        }
        // Split before decoding so an encoded slash cannot introduce a new ZIP component.
        let components = try parts.percentEncodedPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map { encoded in
            guard let decoded = String(encoded).removingPercentEncoding,
                  !decoded.contains("/"), !decoded.contains("\\"), !decoded.contains("\0"),
                  !decoded.isEmpty, decoded != ".", decoded != ".." else { throw LocalLibraryError.invalidBook }
            return decoded
        }
        let path = components.joined(separator: "/")
        guard try EpubArchive.normalized(path) == path else { throw LocalLibraryError.invalidBook }
        return path
    }

    public static func mimeType(path: String, publication: EpubPublication) -> String {
        if (try? EpubArchive.normalized(path)) == path,
           let item = publication.manifest.first(where: { $0.href == path }) { return item.mediaType }
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "text/html"
        case "xhtml": return "application/xhtml+xml"
        case "css": return "text/css"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}
