import Foundation

extension LocalLibrary {
    public func importPdf(title: String, file source: URL, inspect: (URL) throws -> PdfPublication,
                          renderCover: (URL) throws -> Data?) throws -> LocalBook {
        try Task.checkCancellation()
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard source.isFileURL, attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw LocalLibraryError.invalidBook }
        guard let size = attributes.fileSize, Int64(size) <= Self.maximumImportBytes else { throw LocalLibraryError.folderTooLarge }
        let id = UUID().uuidString, manager = FileManager.default
        let staging = directory.appendingPathComponent(".import-" + id, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { if manager.fileExists(atPath: staging.path) { try? manager.removeItem(at: staging) } }
        let content = staging.appendingPathComponent("content.pdf")
        var copied: Int64 = 0
        try copy(source, to: content, totalBytes: &copied, maximumFileBytes: Self.maximumImportBytes)
        let publication = try inspect(content)
        try publication.validate()
        let cover = try renderCover(content)
        try Task.checkCancellation()
        if let cover {
            guard !cover.isEmpty, cover.count <= Self.maximumImageBytes else { throw PdfError.renderFailed }
            try cover.write(to: staging.appendingPathComponent("cover.bin"), options: .atomic)
        }
        let names = publication.pages.indices.map { "pdf-\($0)" }
        let cleaned = SearchRules.trim(title)
        let book = LocalBook(id: id, title: cleaned.isEmpty ? "本地 PDF" : cleaned, createdAt: Date().timeIntervalSince1970,
                             pages: names, chapters: [LocalBookChapter(id: id + "_ch_0", title: "全本", pages: names)],
                             pdf: publication, coverName: cover == nil ? nil : "cover.bin")
        try validatePdfMetadata(book)
        try JSONEncoder().encode(book).write(to: staging.appendingPathComponent("book.json"), options: .atomic)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: directory.appendingPathComponent(id, isDirectory: true))
        return book
    }

    public func pdfPageData(pageURL: URL, render: (URL, Int) throws -> Data) throws -> Data {
        try Task.checkCancellation()
        let token = try LocalPageURL.parse(pageURL, scheme: "xxcomic-pdf")
        let book = try book(id: token.bookID)
        guard let publication = book.pdf, publication.pages.indices.contains(token.index) else { throw LocalLibraryError.invalidBook }
        let bytes = try render(ownedFile(bookID: book.id, name: "content.pdf"), token.index)
        try Task.checkCancellation()
        guard !bytes.isEmpty, bytes.count <= Self.maximumImageBytes else { throw PdfError.renderFailed }
        return bytes
    }

    func validatePdf(_ book: LocalBook) throws {
        try validatePdfMetadata(book)
        let content = try ownedFile(bookID: book.id, name: "content.pdf")
        guard let size = try content.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) <= Self.maximumImportBytes else { throw LocalLibraryError.invalidBook }
        if let cover = book.coverName { _ = try ownedFile(bookID: book.id, name: cover) }
    }

    private func validatePdfMetadata(_ book: LocalBook) throws {
        guard book.epub == nil, let publication = book.pdf,
              book.pages == publication.pages.indices.map({ "pdf-\($0)" }),
              book.coverName == nil || book.coverName == "cover.bin",
              book.chapters == [LocalBookChapter(id: book.id + "_ch_0", title: "全本", pages: book.pages)] else { throw LocalLibraryError.invalidBook }
        try publication.validate()
    }
}
