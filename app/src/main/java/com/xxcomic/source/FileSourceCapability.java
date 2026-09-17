package com.xxcomic.source;

import java.io.IOException;
import java.util.List;

/**
 * Optional capability for sources that distribute full archive/book files (ZIP, EPUB, PDF, MOBI, etc.)
 * rather than individual page image URLs.
 */
public interface FileSourceCapability {
    /**
     * Lists all files/volumes available for the given comic.
     */
    List<FileResource> listFiles(String comicId) throws IOException;

    /**
     * Resolves an up-to-date download description for a specific file/volume.
     * Can refresh short-lived signed URLs.
     */
    FileResource resolveFile(String comicId, String fileId) throws IOException;
}
