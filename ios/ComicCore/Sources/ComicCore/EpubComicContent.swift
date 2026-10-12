import Foundation

/// Import policy for image comics. The parser still decodes old publication metadata,
/// but the app never renders XHTML text or silently drops text from a mixed book.
enum EpubComicContent {
    static func validate(_ publication: EpubPublication, archive: EpubArchive) throws {
        guard !publication.spine.isEmpty, publication.spine.allSatisfy({ $0.resolvedImageEntry != nil }) else {
            throw LocalLibraryError.unsupportedTextContent
        }
        for item in publication.spine {
            try Task.checkCancellation()
            if ["application/xhtml+xml", "text/html"].contains(item.mediaType.lowercased()) {
                let data = try archive.read(item.fullZipPath, maximumBytes: 8 * 1024 * 1024)
                try validateMarkup(String(decoding: data, as: UTF8.self), expectedImages: 1)
            }
        }
    }

    /// A linear, bounded markup inspection; it does not execute scripts, load resources,
    /// resolve entities or apply CSS. Text in the body remains unsupported even if hidden.
    static func validateMarkup(_ html: String, expectedImages: Int? = nil) throws {
        let bytes = Array(html.utf8)
        var offset = bytes.starts(with: [239, 187, 191]) ? 3 : 0
        var imageCount = 0
        var ignored: [String] = []
        let metadata: Set<String> = ["head", "title", "desc", "metadata", "style", "script"]
        while offset < bytes.count {
            try Task.checkCancellation()
            if bytes[offset] != 60 {
                let start = offset
                while offset < bytes.count, bytes[offset] != 60 {
                    if offset % 4096 == 0 { try Task.checkCancellation() }
                    offset += 1
                }
                if ignored.isEmpty, hasText(String(decoding: bytes[start..<offset], as: UTF8.self)) {
                    throw LocalLibraryError.unsupportedTextContent
                }
                continue
            }
            if bytes[offset...].starts(with: [60, 33, 45, 45]) {
                offset += 4
                while offset + 2 < bytes.count, !bytes[offset...].starts(with: [45, 45, 62]) {
                    if offset % 4096 == 0 { try Task.checkCancellation() }
                    offset += 1
                }
                guard offset + 2 < bytes.count else { throw LocalLibraryError.unsupportedTextContent }
                offset += 3
                continue
            }
            let start = offset + 1
            offset = start
            var quote: UInt8?
            while offset < bytes.count {
                if offset % 4096 == 0 { try Task.checkCancellation() }
                let byte = bytes[offset]
                if let current = quote { if byte == current { quote = nil } }
                else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 { break }
                offset += 1
            }
            guard offset < bytes.count else { throw LocalLibraryError.unsupportedTextContent }
            let token = String(decoding: bytes[start..<offset], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            offset += 1
            guard !token.hasPrefix("![CDATA[") else { throw LocalLibraryError.unsupportedTextContent }
            let closing = token.hasPrefix("/")
            let name = token.drop(while: { $0 == "/" }).prefix(while: { !$0.isWhitespace && $0 != "/" })
                .split(separator: ":").last.map(String.init)?.lowercased() ?? ""
            if closing {
                if ignored.last == name { ignored.removeLast() }
            } else if metadata.contains(name), !token.hasSuffix("/") {
                guard ignored.count < 128 else { throw LocalLibraryError.unsupportedTextContent }
                ignored.append(name)
            } else if ignored.isEmpty {
                if name == "img" || name == "image" { imageCount += 1 }
                if ["iframe", "object", "canvas", "video", "audio", "math"].contains(name) {
                    throw LocalLibraryError.unsupportedTextContent
                }
            }
        }
        guard ignored.isEmpty, expectedImages.map({ imageCount == $0 }) ?? true else {
            throw LocalLibraryError.unsupportedTextContent
        }
    }

    private static func hasText(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { index = scalars.index(after: index); continue }
            guard scalar == "&" else { return true }
            var end = scalars.index(after: index), count = 0
            while end < scalars.endIndex, scalars[end] != ";", count < 32 { end = scalars.index(after: end); count += 1 }
            guard end < scalars.endIndex, scalars[end] == ";" else { return true }
            end = scalars.index(after: end)
            let decoded = HTML4EntityDecoder.decode(String(scalars[index..<end]))
            guard decoded.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { return true }
            index = end
        }
        return false
    }
}
