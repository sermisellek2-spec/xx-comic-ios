package com.xxcomic.local;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;

/** Desktop codec for JVM indexing tests only. Native BitmapFactory is tested by device checks. */
final class LocalImageFixtures {
    static final ArchiveIndex.ImageProbe PROBE = source -> {
        try (InputStream in = source.open()) {
            try {
                // Android's javac bootclasspath excludes desktop codecs; keep this adapter in tests only.
                return Class.forName("javax.imageio.ImageIO").getMethod("read", InputStream.class).invoke(null, in) != null;
            } catch (java.lang.reflect.InvocationTargetException invalidImage) {
                return false;
            } catch (ReflectiveOperationException unavailable) {
                throw new IOException("Desktop test codec unavailable", unavailable);
            }
        }
    };

    static ArchiveIndex.ParseResult indexArchive(File file, String id) throws IOException {
        return ArchiveIndex.indexArchive(file, id, null, PROBE);
    }

    static ArchiveIndex.ParseResult indexArchive(File file, String id, LocalModels.ImportProgressCallback cancel) throws IOException {
        return ArchiveIndex.indexArchive(file, id, cancel, PROBE);
    }

    static LocalImporter.FolderIndexResult indexFolder(File file) throws IOException {
        return LocalImporter.indexFolder(file, null, PROBE);
    }

    static LocalImporter.FolderIndexResult indexFolder(File file, LocalModels.ImportProgressCallback cancel) throws IOException {
        return LocalImporter.indexFolder(file, cancel, PROBE);
    }
}
