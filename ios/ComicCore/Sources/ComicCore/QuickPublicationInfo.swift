import Foundation

/// Metadata-only suggestions for later import grouping; no body or image decoding.
public struct QuickPublicationInfo: Equatable, Sendable {
    public let title: String
    public let seriesTitle: String
    /// Keep the original decimal text so later sorting does not lose precision.
    public let volumeNumber: String
    public let coverEntry: String
    /// For EPUB, this only means metadata was scanned, not that body/DRM checks passed.
    public let isReadable: Bool
    public let unsupportedReason: String?

    public static func read(_ file: URL, formatOrFileName: String? = nil) throws -> Self {
        try Task.checkCancellation()
        let format = (formatOrFileName ?? file.lastPathComponent).components(separatedBy: ".").last!.lowercased()
        if ["mobi", "azw", "azw3", "prc"].contains(format) {
            let result = try KindleFormatDetector.detect(file)
            return Self(title: result.title, seriesTitle: "", volumeNumber: "", coverEntry: "",
                        isReadable: result.isReadable, unsupportedReason: result.unsupportedReason)
        }
        guard format == "epub" else { throw EpubError.invalid("不支持的电子书格式: \(format)") }
        let archive = try EpubArchive(url: file, maximumReadBytes: 2 * 1024 * 1024)
        func readXML(_ path: String) throws -> EpubXML.Node {
            try EpubXML.parse(archive.read(path, maximumBytes: 1024 * 1024), path: path)
        }
        let container = try readXML("META-INF/container.xml")
        var opf = ""
        for root in container.descendants("rootfile") {
            try Task.checkCancellation()
            let path = SearchRules.trim(root["full-path"])
            if !path.isEmpty && (opf.isEmpty || root["media-type"] == "application/oebps-package+xml") { opf = path }
        }
        opf = try resolve(opf)
        let document = try readXML(opf)
        var title = "", series = "", volume = "", coverID = "", cover = ""
        if let metadata = document.descendants("metadata").first {
            title = SearchRules.trim(metadata.descendants("title").first?.text ?? "")
            let metas = metadata.descendants("meta")
            for meta in metas {
                try Task.checkCancellation()
                switch meta["name"] {
                case "calibre:series": series = SearchRules.trim(meta["content"])
                case "calibre:series_index": volume = SearchRules.trim(meta["content"])
                case "cover": coverID = meta["content"]
                default: break
                }
            }
            if series.isEmpty {
                // Byte keys preserve Java ID equality; index once, keeping each property's last value.
                var refinements: [Data: (type: String, position: String)] = [:]
                for meta in metas {
                    try Task.checkCancellation()
                    let key = Data(meta["refines"].utf8)
                    if meta["property"] == "collection-type" {
                        refinements[key, default: ("", "")].type = SearchRules.trim(meta.text)
                    } else if meta["property"] == "group-position" {
                        refinements[key, default: ("", "")].position = SearchRules.trim(meta.text)
                    }
                }
                for meta in metas {
                    try Task.checkCancellation()
                    guard meta["property"] == "belongs-to-collection", !meta["id"].isEmpty,
                          let refinement = refinements[Data(("#" + meta["id"]).utf8)], refinement.type == "series" else { continue }
                    series = SearchRules.trim(meta.text)
                    volume = refinement.position
                    break
                }
            }
        }
        for item in document.descendants("item") {
            try Task.checkCancellation()
            let hasCoverProperty = item["properties"].components(separatedBy: CharacterSet(charactersIn: " \t\n\r\u{0b}\u{0c}")).contains("cover-image")
            if hasCoverProperty || (!coverID.isEmpty && item["id"].utf16.elementsEqual(coverID.utf16)) {
                cover = try resolve(item["href"], relativeTo: opf)
                break
            }
        }
        try Task.checkCancellation()
        return Self(title: title, seriesTitle: series, volumeNumber: volume, coverEntry: cover,
                    isReadable: true, unsupportedReason: nil)
    }

    private static func resolve(_ raw: String, relativeTo opf: String = "") throws -> String {
        // Unlike the full reader's form decoding, metadata URI paths retain literal '+'.
        guard let decoded = raw.removingPercentEncoding else { throw EpubError.invalid("EPUB 元数据路径编码无效") }
        let path = decoded.replacingOccurrences(of: "\\", with: "/")
        // Validate the relative reference before combining it with the OPF directory.
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(":"), !path.contains("\0") else {
            throw EpubError.invalid("EPUB 元数据路径无效")
        }
        let base = opf.lastIndex(of: "/").map { String(opf[...$0]) } ?? ""
        return try EpubArchive.normalized(base + path)
    }
}
