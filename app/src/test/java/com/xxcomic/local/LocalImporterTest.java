package com.xxcomic.local;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class LocalImporterTest {
    private File tempDir;
    private static final byte[] FAKE_PNG_BYTES = new byte[]{
            (byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 'I', 'H', 'D', 'R'
    };

    @Before
    public void setUp() throws IOException {
        tempDir = Files.createTempDirectory("local_importer_test").toFile();
    }

    @After
    public void tearDown() {
        if (tempDir != null && tempDir.exists()) {
            deleteRecursive(tempDir);
        }
    }

    private void deleteRecursive(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) deleteRecursive(child);
            }
        }
        file.delete();
    }

    private void writeFile(File file, byte[] data) throws IOException {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(data);
        }
    }

    @Test
    public void testFolderManifestFingerprintStability() throws Exception {
        File folder1 = new File(tempDir, "comic_a");
        writeFile(new File(folder1, "ch1/01.png"), FAKE_PNG_BYTES);
        writeFile(new File(folder1, "ch1/02.png"), FAKE_PNG_BYTES);

        LocalImporter.FolderIndexResult idx1 = LocalImporter.indexFolder(folder1);
        assertEquals(2, idx1.validImages.size());

        String fp1 = LocalImporter.computeFolderManifestFingerprint(folder1, idx1.validImages);
        assertNotNull(fp1);

        // Same folder content in another folder should yield the exact same fingerprint
        File folder2 = new File(tempDir, "comic_b");
        writeFile(new File(folder2, "ch1/01.png"), FAKE_PNG_BYTES);
        writeFile(new File(folder2, "ch1/02.png"), FAKE_PNG_BYTES);

        LocalImporter.FolderIndexResult idx2 = LocalImporter.indexFolder(folder2);
        String fp2 = LocalImporter.computeFolderManifestFingerprint(folder2, idx2.validImages);
        assertEquals(fp1, fp2);

        // Modifying content should change fingerprint
        byte[] differentBytes = Arrays.copyOf(FAKE_PNG_BYTES, FAKE_PNG_BYTES.length + 1);
        writeFile(new File(folder2, "ch1/02.png"), differentBytes);
        String fp3 = LocalImporter.computeFolderManifestFingerprint(folder2, idx2.validImages);
        assertNotEquals(fp1, fp3);
    }

    @Test
    public void testBuildFolderChaptersWithWrapper() {
        List<String> paths = Arrays.asList(
                "WrapperDir/第1话/01.png",
                "WrapperDir/第1话/02.png",
                "WrapperDir/第2话/01.png"
        );
        LocalImporter.FolderChaptersResult result = LocalImporter.buildFolderChapters(tempDir, paths, "book_f");
        assertEquals(2, result.chapters.size());
        assertEquals("第1话", result.chapters.get(0).title);
        assertEquals("第2话", result.chapters.get(1).title);
        assertEquals(3, result.totalPages);
    }

    @Test
    public void testBuildFolderChaptersFlat() {
        List<String> paths = Arrays.asList(
                "10.png",
                "1.png",
                "2.png"
        );
        LocalImporter.FolderChaptersResult result = LocalImporter.buildFolderChapters(tempDir, paths, "book_flat");
        assertEquals(1, result.chapters.size());
        assertEquals("正文", result.chapters.get(0).title);
        assertEquals(3, result.totalPages);
        List<LocalModels.Page> pages = result.pagesByChapter.get(result.chapters.get(0).id);
        assertEquals("1.png", pages.get(0).entryPath);
        assertEquals("2.png", pages.get(1).entryPath);
        assertEquals("10.png", pages.get(2).entryPath);
    }
}
