import Foundation

public enum EpubParser {
    public static func parse(archive url: URL) throws -> EpubPublication {
        let archive = try EpubArchive(url: url)
        let container = try xml("META-INF/container.xml", archive)
        var selected: String?
        for rootfile in container.descendants("rootfile") {
            let path = SearchRules.trim(rootfile["full-path"])
            if !path.isEmpty && (selected == nil || rootfile["media-type"].lowercased() == "application/oebps-package+xml") { selected = path }
        }
        guard let selected else { throw EpubError.invalid("META-INF/container.xml 缺少有效的 rootfile full-path") }
        let opfPath = try EpubArchive.resolve(selected)
        var hasDrm = false, hasFontObfuscation = false
        if archive.contains("META-INF/encryption.xml") {
            let encryption = try xml("META-INF/encryption.xml", archive)
            for encrypted in encryption.descendants("EncryptedData") {
                let algorithm = encrypted.descendants("EncryptionMethod").first?["Algorithm"] ?? ""
                let uri = encrypted.descendants("CipherReference").first?["URI"] ?? ""
                if ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc/mono/"].contains(algorithm)
                    || [".otf", ".ttf", ".woff", ".woff2"].contains(where: uri.hasSuffix) { hasFontObfuscation = true }
                else { hasDrm = true }
            }
        }
        let document = try xml(opfPath, archive)
        let metadata = document.descendants("metadata").first
        func field(_ name: String) -> String {
            let values = metadata?.descendants(name) ?? []
            return SearchRules.trim((values.first { $0.qualifiedName == "dc:\(name)" } ?? values.first)?.text ?? "")
        }
        var metaCoverID: String?, cover: String?, navPath: String?, ncxPath: String?
        var fixed = false
        for meta in metadata?.descendants("meta") ?? [] {
            if meta["name"].lowercased() == "cover" { metaCoverID = meta["content"] }
            if meta["property"].lowercased() == "rendition:layout", SearchRules.trim(meta.text).lowercased() == "pre-paginated" { fixed = true }
        }
        guard let manifestNode = document.descendants("manifest").first else { throw EpubError.invalid("OPF 缺少 manifest 节点") }
        let items = manifestNode.descendants("item")
        guard !items.isEmpty else { throw EpubError.invalid("manifest 为空") }
        var manifest: [EpubPublication.ManifestItem] = [], byID: [String: EpubPublication.ManifestItem] = [:]
        for item in items {
            try Task.checkCancellation()
            let id = SearchRules.trim(item["id"]), href = SearchRules.trim(item["href"])
            guard !id.isEmpty else { throw EpubError.invalid("manifest 包含缺少 id 的条目") }
            guard byID[id] == nil else { throw EpubError.invalid("manifest 包含重复的条目 id：\(id)") }
            guard !href.isEmpty else { throw EpubError.invalid("manifest item [\(id)] 缺少 href") }
            let path = try EpubArchive.resolve(href, relativeTo: opfPath)
            let media = item["media-type"], properties = item["properties"]
            if properties.contains("cover-image") { cover = path }
            if properties.contains("nav") { navPath = path }
            if media.lowercased() == "application/x-dtbncx+xml" { ncxPath = path }
            if properties.contains("rendition:layout-pre-paginated") { fixed = true }
            let value = EpubPublication.ManifestItem(id: id, href: path, mediaType: media, properties: properties)
            manifest.append(value); byID[id] = value
        }
        guard let spineNode = document.descendants("spine").first else { throw EpubError.invalid("OPF 缺少 spine 节点") }
        if ncxPath == nil { ncxPath = byID[SearchRules.trim(spineNode["toc"])]?.href }
        let references = spineNode.descendants("itemref")
        guard !references.isEmpty else { throw EpubError.invalid("spine 为空") }
        var spine: [EpubPublication.SpineItem] = []
        for reference in references {
            try Task.checkCancellation()
            let id = SearchRules.trim(reference["idref"])
            guard !id.isEmpty else { throw EpubError.invalid("spine itemref 缺少 idref") }
            guard let item = byID[id] else { throw EpubError.invalid("spine 引用了 manifest 中不存在的条目：\(id)") }
            var image: String?
            if item.mediaType.hasPrefix("image/") { image = item.href }
            else if ["application/xhtml+xml", "text/html"].contains(item.mediaType.lowercased()) { image = try singleImage(item.href, archive) }
            spine.append(.init(idref: id, fullZipPath: item.href, mediaType: item.mediaType, linear: reference["linear"].lowercased() != "no", resolvedImageEntry: image))
        }
        var navItems: [EpubPublication.NavItem] = []
        if let navPath, archive.contains(navPath) {
            do { navItems = try navigation(navPath, archive, spine, ncx: false) }
            catch EpubError.invalidXML { /* Ordinary malformed navigation may fall back to NCX. */ }
        }
        if navItems.isEmpty, let ncxPath, archive.contains(ncxPath) {
            do { navItems = try navigation(ncxPath, archive, spine, ncx: true) }
            catch EpubError.invalidXML { /* A book without usable navigation remains readable. */ }
        }
        let imageCount = spine.filter { $0.resolvedImageEntry != nil }.count
        let purePicture = imageCount == spine.count
        let reflowable = !purePicture && imageCount == 0 && manifest.filter { $0.mediaType.hasPrefix("image/") }.count <= 1
        if cover == nil, let metaCoverID, let item = byID[metaCoverID] {
            if item.mediaType.hasPrefix("image/") { cover = item.href }
            else if item.mediaType.lowercased() == "application/xhtml+xml" { cover = try singleImage(item.href, archive) }
        }
        if cover == nil { cover = spine.first?.resolvedImageEntry }
        if cover == nil { cover = manifest.first { $0.mediaType.hasPrefix("image/") && $0.href.lowercased().contains("cover") }?.href }
        try Task.checkCancellation()
        return EpubPublication(title: field("title"), author: field("creator"), description: field("description"), language: field("language"),
                               opfPath: opfPath, coverEntry: cover, manifest: manifest, spine: spine, navItems: navItems,
                               isFixedLayout: fixed, isPurePictureEpub: purePicture, isReflowableText: reflowable,
                               hasDrm: hasDrm, hasFontObfuscation: hasFontObfuscation,
                               unsupportedReason: hasDrm ? "该 EPUB 包含受保护或加密的版权内容 (DRM)" : nil)
    }

    private static func xml(_ path: String, _ archive: EpubArchive) throws -> EpubXML.Node {
        try EpubXML.parse(archive.read(path), path: path)
    }

    private static func singleImage(_ path: String, _ archive: EpubArchive) throws -> String? {
        guard archive.contains(path) else { return nil }
        let html = String(decoding: try archive.read(path, maximumBytes: 1024 * 1024, prefixOnly: true), as: UTF8.self)
        // Match Android's bounded wrapper inspection, including text around a single image.
        let patterns = [#"<img[^>]+src\s*=\s*['"]([^'"]+)['"]"#, #"<image[^>]+(?:xlink:href|href)\s*=\s*['"]([^'"]+)['"]"#]
        var sources: [String] = []
        // ICU can backtrack quadratically on malformed tags. Its progress callback can stop
        // an in-flight match; the two patterns share one monotonic 500 ms time budget.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        var callbacks = 0
        var matchingError: Error?
        for pattern in patterns {
            try Task.checkCancellation()
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            regex.enumerateMatches(in: html, options: .reportProgress, range: NSRange(html.startIndex..., in: html)) { match, _, stop in
                callbacks += 1
                if Task.isCancelled { matchingError = CancellationError() }
                else if callbacks % 128 == 0 && ContinuousClock.now >= deadline {
                    matchingError = EpubError.limitExceeded("XHTML 单图检查超过 500 毫秒：\(path)")
                }
                if matchingError != nil { stop.pointee = true; return }
                if let match, let range = Range(match.range(at: 1), in: html) { sources.append(String(html[range])) }
            }
            if let matchingError { throw matchingError }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw EpubError.limitExceeded("XHTML 单图检查超过 500 毫秒：\(path)") }
        }
        guard sources.count == 1 else { return nil }
        let resolved = try EpubArchive.resolve(sources[0], relativeTo: path)
        return archive.contains(resolved) ? resolved : nil
    }

    private static func navigation(_ path: String, _ archive: EpubArchive, _ spine: [EpubPublication.SpineItem], ncx: Bool) throws -> [EpubPublication.NavItem] {
        let document = try xml(path, archive)
        var indices: [String: Int] = [:]
        for (index, item) in spine.enumerated() where indices[item.fullZipPath] == nil { indices[item.fullZipPath] = index }
        func point(_ node: EpubXML.Node) throws -> EpubPublication.NavItem {
            try Task.checkCancellation()
            let anchor = node.descendants(ncx ? "content" : "a").first
            let raw = anchor?[ncx ? "src" : "href"] ?? ""
            let href = SearchRules.trim(raw).isEmpty ? "" : try EpubArchive.resolve(raw, relativeTo: path)
            let title = SearchRules.trim(ncx ? (node.descendants("text").first?.text ?? "") : (anchor?.text ?? ""))
            let children = ncx ? node.children.filter { $0.name.lowercased() == "navpoint" }
                : (node.descendants("ol").first?.children.filter { $0.name.lowercased() == "li" } ?? [])
            return try .init(title: title, href: href, spineIndex: indices[href] ?? -1, children: children.map(point))
        }
        if ncx {
            return try (document.descendants("navMap").first?.children.filter { $0.name.lowercased() == "navpoint" } ?? []).map(point)
        }
        var toc: EpubXML.Node?
        for nav in document.descendants("nav") {
            if toc == nil || nav["epub:type"].lowercased() == "toc" { toc = nav }
        }
        return try (toc?.descendants("ol").first?.children.filter { $0.name.lowercased() == "li" } ?? []).map(point)
    }
}
