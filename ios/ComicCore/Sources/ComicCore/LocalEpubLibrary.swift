import Foundation

/// The sole encoder/decoder for local EPUB image page identifiers.
enum EpubPageURL {
    static func make(bookID: String, index: Int) throws -> URL {
        try LocalPageURL.make(bookID: bookID, index: index, scheme: "xxcomic-epub")
    }
    static func parse(_ url: URL) throws -> (bookID: String, index: Int) {
        try LocalPageURL.parse(url, scheme: "xxcomic-epub")
    }
}

/// Shared strict encoding for owned EPUB/PDF logical pages; never accepts a file URL.
enum LocalPageURL {
    static func make(bookID: String, index: Int, scheme: String) throws -> URL {
        guard UUID(uuidString: bookID) != nil, index >= 0,
              let url = URL(string: "\(scheme)://page/\(bookID)/\(index)") else { throw LocalLibraryError.invalidBook }
        return url
    }

    static func parse(_ url: URL, scheme: String) throws -> (bookID: String, index: Int) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == scheme, parts.percentEncodedHost == "page", parts.user == nil, parts.password == nil,
              url.absoluteString.hasPrefix("\(scheme)://page/"),
              parts.port == nil, parts.query == nil, parts.fragment == nil,
              !parts.percentEncodedPath.contains("%") else { throw LocalLibraryError.invalidBook }
        if let authority = url.absoluteString.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false).dropFirst(2).first,
           authority.contains(":") { throw LocalLibraryError.invalidBook }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 3, path[0].isEmpty, UUID(uuidString: String(path[1])) != nil,
              !path[2].isEmpty, path[2].utf8.allSatisfy({ (48...57).contains($0) }),
              let index = Int(path[2]) else { throw LocalLibraryError.invalidBook }
        return (String(path[1]), index)
    }
}

extension LocalLibrary {
    public func importEpub(title: String, archive source: URL, isReadableImage: (URL) throws -> Bool) throws -> LocalBook {
        try publishPrepared(prepareEpub(title: title, archive: source, isReadableImage: isReadableImage))
    }
    func prepareEpub(title: String, archive source: URL, isReadableImage: (URL) throws -> Bool) throws -> PreparedLocalImport {
        try prepareOwnedEpub(title: title, isReadableImage: isReadableImage) { staging, owned in
            try copyEbook(source, to: staging.appendingPathComponent("content.epub"), didCreateFile: owned.recordFile)
        }
    }

    func copyEbook(_ source: URL, to destination: URL, didCreateFile: (URL) throws -> Void = { _ in }) throws {
        try Task.checkCancellation()
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard source.isFileURL, attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
        guard let size = attributes.fileSize, Int64(size) <= Self.maximumImportBytes else { throw LocalLibraryError.archiveTooLarge }
        var copied: Int64 = 0
        try copy(source, to: destination, totalBytes: &copied, maximumFileBytes: Self.maximumImportBytes, didCreateFile: didCreateFile)
    }

    /// Original and derived files share the same preparation lifetime.
    func prepareOwnedEpub(title: String, kindleFormat: LocalKindleFormat? = nil,
                         isReadableImage: (URL) throws -> Bool, prepare: (URL, LocalImportDirectory) throws -> Void) throws -> PreparedLocalImport {
        try prepareLocalImport { id, staging, owned in
            let manager = FileManager.default
            let content = staging.appendingPathComponent("content.epub"), probe = staging.appendingPathComponent("probe.bin")
            try prepare(staging, owned)
            let publication = try EpubParser.parse(archive: content)
            let ranges = try publication.chapterRanges() // Rejects DRM and empty spine before probing.
            let archive = try EpubArchive(url: content, maximumReadBytes: UInt64(Self.maximumImportBytes))
            var validated = Set<String>(), validImages = Set<String>(), invalidImages = Set<String>(), coverName: String?

            func writeProbe(_ path: String) throws {
                // Each extraction replaces probe.bin; release only the previous owned inode.
                try owned.removeFile(probe)
                try archive.write(path, to: probe)
                try owned.recordFile(probe)
            }

            func validateImage(_ path: String, required: Bool) throws {
                try Task.checkCancellation()
                if invalidImages.contains(path) {
                    if required { throw EpubError.invalid("正文图片不可读取：\(path)") }
                    return
                }
                if validImages.contains(path) { return }
                guard archive.contains(path) else {
                    if required { throw EpubError.invalid("缺少正文图片：\(path)") }
                    return
                }
                try writeProbe(path)
                let readable = try isReadableImage(probe)
                try owned.recordFile(probe)
                try Task.checkCancellation()
                if readable {
                    validated.insert(path)
                    validImages.insert(path)
                    if coverName == nil {
                        try manager.moveItem(at: probe, to: staging.appendingPathComponent("cover.bin"))
                        try owned.recordFile(probe)
                        try owned.recordFile(staging.appendingPathComponent("cover.bin"))
                        coverName = "cover.bin"
                    }
                } else {
                    invalidImages.insert(path)
                    if required { throw EpubError.invalid("正文图片不可读取：\(path)") }
                }
            }

            if let candidate = publication.coverEntry { try validateImage(candidate, required: false) }
            for item in publication.spine {
                try Task.checkCancellation()
                if let image = item.resolvedImageEntry { try validateImage(image, required: true) }
                if validated.insert(item.fullZipPath).inserted {
                    // Text and image wrappers also receive full CRC validation without retaining Data.
                    try writeProbe(item.fullZipPath)
                }
            }
            if coverName == nil, let candidate = publication.manifest.first(where: { $0.mediaType.hasPrefix("image/") }) {
                try validateImage(candidate.href, required: false)
            }
            try owned.removeFile(probe)
            let names = publication.spine.indices.map { "spine-\($0)" }
            let chapters = ranges.enumerated().map { index, range in
                LocalBookChapter(id: id + "_ch_\(index)", title: range.title, pages: Array(names[range.startIndex..<range.endIndex]))
            }
            let cleaned = SearchRules.trim(title)
            let format: LocalImportFormat
            let hashTarget: URL
            if let kindleFormat {
                switch kindleFormat {
                case .mobi: format = .mobi
                case .azw: format = .azw
                case .azw3: format = .azw3
                }
                hashTarget = staging.appendingPathComponent("source.kindle")
            } else {
                format = .epub
                hashTarget = content
            }
            let fingerprint = try ContentFingerprint.file(hashTarget)
            let book = LocalBook(id: id, title: cleaned.isEmpty ? (publication.title.isEmpty ? "本地 EPUB" : publication.title) : cleaned,
                                 createdAt: Date().timeIntervalSince1970, pages: names, chapters: chapters, epub: publication, coverName: coverName,
                                 kindleFormat: kindleFormat, importFormat: format, fingerprint: fingerprint)
            try validateEpubMetadata(book)
            return book
        }
    }

    public func epubResource(bookID: String, path: String, maximumBytes: Int) throws -> Data {
        try Task.checkCancellation()
        let book = try book(id: bookID)
        guard book.epub != nil, try EpubArchive.normalized(path) == path else { throw LocalLibraryError.invalidBook }
        // Each caller owns an independent archive; no ZIPFoundation instance crosses workers.
        let archive = try EpubArchive(url: ownedEPUB(book))
        return try archive.read(path, maximumBytes: maximumBytes)
    }

    public func epubImageData(pageURL: URL) throws -> Data {
        let token = try EpubPageURL.parse(pageURL)
        let book = try book(id: token.bookID)
        guard let publication = book.epub, publication.spine.indices.contains(token.index) else { throw LocalLibraryError.invalidBook }
        guard let path = publication.spine[token.index].resolvedImageEntry else { throw LocalLibraryError.requiresTextReader }
        return try epubResource(bookID: book.id, path: path, maximumBytes: Self.maximumImageBytes)
    }

    /// Only direct, regular files in a directly owned UUID directory may be opened.
    func ownedFile(bookID: String, name: String) throws -> URL {
        guard UUID(uuidString: bookID) != nil, !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else { throw LocalLibraryError.invalidBook }
        let folder = directory.appendingPathComponent(bookID, isDirectory: true), file = folder.appendingPathComponent(name)
        let folderInfo = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let fileInfo = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard folderInfo.isDirectory == true, folderInfo.isSymbolicLink != true,
              fileInfo.isRegularFile == true, fileInfo.isSymbolicLink != true,
              folder.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
              file.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL else {
            throw LocalLibraryError.invalidBook
        }
        return file
    }

    func validateEpub(_ book: LocalBook) throws {
        try validateEpubMetadata(book)
        if book.kindleFormat != nil { _ = try ownedKindle(book) }
        guard try existingOwnedEPUB(book) != nil || book.kindleFormat != nil else { throw LocalLibraryError.invalidBook }
        if let name = book.coverName { _ = try ownedFile(bookID: book.id, name: name) }
    }

    /// Import and reopening must agree before a book becomes visible to the shelf.
    private func validateEpubMetadata(_ book: LocalBook) throws {
        try book.validateMetadata()
        guard let publication = book.epub, !publication.hasDrm,
              !publication.manifest.isEmpty, publication.manifest.count <= 50_000, publication.spine.count <= 100_000,
              book.pages == publication.spine.indices.map({ "spine-\($0)" }),
              book.coverName == nil || book.coverName == "cover.bin" else { throw LocalLibraryError.invalidBook }
        func path(_ value: String) throws {
            guard try EpubArchive.normalized(value) == value else { throw LocalLibraryError.invalidBook }
        }
        try path(publication.opfPath)
        if let cover = publication.coverEntry { try path(cover) }
        var manifest: [String: EpubPublication.ManifestItem] = [:]
        for item in publication.manifest {
            try Task.checkCancellation()
            try path(item.href)
            guard !item.id.isEmpty, manifest.updateValue(item, forKey: item.id) == nil else { throw LocalLibraryError.invalidBook }
        }
        for item in publication.spine {
            try Task.checkCancellation()
            try path(item.fullZipPath)
            guard let declared = manifest[item.idref], declared.href == item.fullZipPath, declared.mediaType == item.mediaType else {
                throw LocalLibraryError.invalidBook
            }
            if let image = item.resolvedImageEntry {
                try path(image)
                guard (item.mediaType.hasPrefix("image/") && image == item.fullZipPath)
                    || ["application/xhtml+xml", "text/html"].contains(item.mediaType.lowercased()) else { throw LocalLibraryError.invalidBook }
            } else if item.mediaType.hasPrefix("image/") { throw LocalLibraryError.invalidBook }
        }
        let imageCount = publication.spine.filter { $0.resolvedImageEntry != nil }.count
        guard publication.isPurePictureEpub == (imageCount == publication.spine.count),
              publication.isReflowableText == (imageCount == 0 && publication.manifest.filter { $0.mediaType.hasPrefix("image/") }.count <= 1) else {
            throw LocalLibraryError.invalidBook
        }
        var pending = publication.navItems, visited = 0
        while let nav = pending.popLast() {
            visited += 1
            guard visited <= 100_000, nav.spineIndex >= -1, nav.spineIndex < publication.spine.count else { throw LocalLibraryError.invalidBook }
            if !nav.href.isEmpty { try path(nav.href) }
            pending.append(contentsOf: nav.children)
        }
        let expected = try publication.chapterRanges().enumerated().map { index, range in
            LocalBookChapter(id: book.id + "_ch_\(index)", title: range.title, pages: Array(book.pages[range.startIndex..<range.endIndex]))
        }
        guard book.chapters == expected else { throw LocalLibraryError.invalidBook }
    }
}
