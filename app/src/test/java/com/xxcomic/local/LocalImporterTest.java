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
    @Test
    public void volumeBindingKeepsEveryChapterAndNamespacesPagesByContent() {
        LocalImporter.FolderChaptersResult source = LocalImporter.buildFolderChapters(new File("."),
                Arrays.asList("ch1/1.png", "ch2/1.png"), "temporary");
        ArchiveIndex.ParseResult index = new ArchiveIndex.ParseResult(source.chapters, source.pagesByChapter,
                source.totalPages, 0, null, Collections.emptyList());
        LocalModels.Volume volume = new LocalModels.Volume("series_vol_hash", "series", "hash", "卷2",
                "epub", "volume.epub", 20, 1, "ready", 0, 0);
        ArchiveIndex.ParseResult bound = LocalImporter.bindVolume(index, volume);
        assertEquals(2, bound.chapters.size());
        assertEquals("series_vol_hash_ch_0", bound.chapters.get(0).id);
        assertEquals("series_vol_hash_ch_1", bound.chapters.get(1).id);
        assertEquals("series", bound.chapters.get(1).bookId);
        assertEquals("series_vol_hash", bound.chapters.get(1).volumeId);
        assertEquals("volume.epub", bound.chapters.get(1).entryPath);
        assertEquals("ch2/1.png", bound.pagesByChapter.get("series_vol_hash_ch_1").get(0).entryPath);
        assertEquals("series_vol_hash_ch_1_p_0", bound.pagesByChapter.get("series_vol_hash_ch_1").get(0).id);
    }
    @Test
    public void cancellationInterruptsDecoderReadsEvenWhenDecoderSwallowsIOException() throws Exception {
        java.util.concurrent.atomic.AtomicBoolean cancelled = new java.util.concurrent.atomic.AtomicBoolean();
        LocalModels.ImportProgressCallback callback = new LocalModels.ImportProgressCallback() {
            @Override public void onProgress(long current, long total, String message) { }
            @Override public boolean isCancelled() { return cancelled.get(); }
        };
        try {
            ArchiveIndex.isDecodableImage(() -> new java.io.ByteArrayInputStream(new byte[1024]), callback, source -> {
                try (java.io.InputStream in = source.open()) {
                    assertEquals(16, in.read(new byte[16]));
                    cancelled.set(true);
                    in.read();
                    org.junit.Assert.fail("decoder read continued after cancellation");
                } catch (IOException ignored) { /* Native decoders may consume stream errors. */ }
                return true;
            });
            org.junit.Assert.fail("cancelled decoder accepted as a valid page");
        } catch (java.io.InterruptedIOException expected) { }
    }

    @Test
    public void boundedStreamAcceptsExactLimitAndRejectsOneByteMore() throws Exception {
        try (java.io.InputStream in = new LocalImporter.BoundedInputStream(
                new java.io.ByteArrayInputStream(new byte[]{1, 2}), 2)) {
            assertEquals(1, in.read());
            assertEquals(2, in.read());
            assertEquals(-1, in.read());
        }
        try {
            try (java.io.InputStream in = new LocalImporter.BoundedInputStream(
                    new java.io.ByteArrayInputStream(new byte[]{1, 2, 3}), 2)) {
                assertEquals(2, in.read(new byte[2]));
                in.read();
                org.junit.Assert.fail("oversized stream accepted");
            }
        } catch (IOException expected) { assertTrue(expected.getMessage().contains("上限")); }
    }
    private File tempDir;
    // Valid 1x1 PNG bytes (starts with 89 50 4E 47 ... followed by valid IHDR with width=1, height=1)
    private static final byte[] VALID_PNG_BYTES = new byte[]{
            (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 'I', 'H', 'D', 'R',
            0x00, 0x00, 0x00, 0x01, // width: 1
            0x00, 0x00, 0x00, 0x01, // height: 1
            0x08, 0x06, 0x00, 0x00, 0x00,
            0x1F, 0x15, (byte) 0xC4, (byte) 0x89,
            0x00, 0x00, 0x00, 0x0A, 'I', 'D', 'A', 'T',
            0x78, (byte) 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, (byte) 0xB4,
            0x00, 0x00, 0x00, 0x00, 'I', 'E', 'N', 'D',
            (byte) 0xAE, 0x42, 0x60, (byte) 0x82
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
        writeFile(new File(folder1, "ch1/01.png"), VALID_PNG_BYTES);
        writeFile(new File(folder1, "ch1/02.png"), VALID_PNG_BYTES);

        LocalImporter.FolderIndexResult idx1 = LocalImageFixtures.indexFolder(folder1);
        assertEquals(2, idx1.validImages.size());

        String fp1 = LocalImporter.computeFolderManifestFingerprint(folder1, idx1.validImages);
        assertNotNull(fp1);

        // Same folder content in another folder should yield the exact same fingerprint
        File folder2 = new File(tempDir, "comic_b");
        writeFile(new File(folder2, "ch1/01.png"), VALID_PNG_BYTES);
        writeFile(new File(folder2, "ch1/02.png"), VALID_PNG_BYTES);

        LocalImporter.FolderIndexResult idx2 = LocalImageFixtures.indexFolder(folder2);
        String fp2 = LocalImporter.computeFolderManifestFingerprint(folder2, idx2.validImages);
        assertEquals(fp1, fp2);

        // Modifying content should change fingerprint
        byte[] differentBytes = Arrays.copyOf(VALID_PNG_BYTES, VALID_PNG_BYTES.length + 1);
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

    @Test
    public void testSanitizeSegmentName() {
        assertEquals("test_name", LocalImporter.sanitizeSegmentName("test_name"));
        assertEquals("abc", LocalImporter.sanitizeSegmentName("../../../abc"));
        assertEquals("file.png", LocalImporter.sanitizeSegmentName("dir/sub\\file.png"));
        assertEquals("unnamed", LocalImporter.sanitizeSegmentName(".."));
        assertEquals("unnamed", LocalImporter.sanitizeSegmentName("."));
        assertEquals("unnamed", LocalImporter.sanitizeSegmentName(""));
        assertEquals("unnamed", LocalImporter.sanitizeSegmentName(null));
    }

    @Test
    public void testFolderDepthLimit() throws IOException {
        File deep = new File(tempDir, "d1/d2/d3/d4/d5/d6");
        deep.mkdirs();
        writeFile(new File(deep, "01.png"), VALID_PNG_BYTES);

        try {
            LocalImageFixtures.indexFolder(tempDir);
            org.junit.Assert.fail("Expected IOException for folder depth exceeding MAX_FOLDER_DEPTH");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("层级过深") || e.getMessage().contains("深度"));
        }
    }

    @Test
    public void testIndexFolderRejectsSignatureOnlyPng() throws IOException {
        File folder = new File(tempDir, "sig_only_folder");
        folder.mkdirs();
        byte[] sigOnly = new byte[]{(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
        writeFile(new File(folder, "sig.png"), sigOnly);

        try {
            LocalImageFixtures.indexFolder(folder);
            org.junit.Assert.fail("Expected IOException for folder without valid decodable images");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("未找到有效的漫画图片"));
        }
    }

    @Test
    public void testComputeFolderManifestFingerprintCancellation() throws Exception {
        File folder = new File(tempDir, "cancel_folder");
        writeFile(new File(folder, "01.png"), VALID_PNG_BYTES);
        List<String> images = Collections.singletonList("01.png");

        LocalModels.ImportProgressCallback cancelledCallback = new LocalModels.ImportProgressCallback() {
            @Override public void onProgress(long currentBytes, long totalBytes, String message) {}
            @Override public boolean isCancelled() { return true; }
        };

        try {
            LocalImporter.computeFolderManifestFingerprint(folder, images, cancelledCallback);
            org.junit.Assert.fail("Expected IOException when callback is cancelled during fingerprint computation");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("用户取消导入"));
        }
    }

    @Test
    public void testFolderIndexingCancellation() throws Exception {
        File folder = new File(tempDir, "cancel_index_folder");
        writeFile(new File(folder, "01.png"), VALID_PNG_BYTES);

        LocalModels.ImportProgressCallback cancelledCallback = new LocalModels.ImportProgressCallback() {
            @Override public void onProgress(long currentBytes, long totalBytes, String message) {}
            @Override public boolean isCancelled() { return true; }
        };

        try {
            LocalImageFixtures.indexFolder(folder, cancelledCallback);
            org.junit.Assert.fail("Expected IOException when callback is cancelled during folder indexing");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("用户取消导入"));
        }
    }

    @Test
    public void testParseTitleAndChapter() {
        // Standard space-hyphen-space
        LocalImporter.ParsedName p1 = LocalImporter.parseTitleAndChapter("狂赌之渊 - 卷02.epub");
        assertTrue(p1.matchedFormat);
        assertEquals("狂赌之渊", p1.comicTitle);
        assertEquals("卷02", p1.chapterTitle);

        // Standard hyphen with PDF
        LocalImporter.ParsedName p2 = LocalImporter.parseTitleAndChapter("狂赌之渊 - 卷01.pdf");
        assertTrue(p2.matchedFormat);
        assertEquals("狂赌之渊", p2.comicTitle);
        assertEquals("卷01", p2.chapterTitle);

        // Hyphen without surrounding spaces
        LocalImporter.ParsedName p3 = LocalImporter.parseTitleAndChapter("进击的巨人-第12卷.cbz");
        assertTrue(p3.matchedFormat);
        assertEquals("进击的巨人", p3.comicTitle);
        assertEquals("第12卷", p3.chapterTitle);

        // Em-dash (—)
        LocalImporter.ParsedName p4 = LocalImporter.parseTitleAndChapter("间谍过家家 — 卷05.epub");
        assertTrue(p4.matchedFormat);
        assertEquals("间谍过家家", p4.comicTitle);
        assertEquals("卷05", p4.chapterTitle);

        // En-dash (–)
        LocalImporter.ParsedName p5 = LocalImporter.parseTitleAndChapter("电锯人 – 卷01.zip");
        assertTrue(p5.matchedFormat);
        assertEquals("电锯人", p5.comicTitle);
        assertEquals("卷01", p5.chapterTitle);

        // Single file without delimiter
        LocalImporter.ParsedName p6 = LocalImporter.parseTitleAndChapter("海贼王01.epub");
        assertFalse(p6.matchedFormat);
        assertEquals("海贼王01", p6.comicTitle);
        assertEquals("全本", p6.chapterTitle);
    }

    @Test
    public void testPseudoPageNavDetection() {
        // Pseudo-page list from comic EPUB (like in user screenshot)
        List<com.xxcomic.ebook.Publication.NavItem> pseudoNav = Arrays.asList(
                new com.xxcomic.ebook.Publication.NavItem("第001页", "p1.xhtml", 0, null),
                new com.xxcomic.ebook.Publication.NavItem("第002页", "p2.xhtml", 1, null),
                new com.xxcomic.ebook.Publication.NavItem("第003页", "p3.xhtml", 2, null),
                new com.xxcomic.ebook.Publication.NavItem("第004页", "p4.xhtml", 3, null)
        );
        assertTrue(com.xxcomic.ebook.Publication.isPseudoPageNav(pseudoNav, 4));

        // Pseudo-page list with "Page X"
        List<com.xxcomic.ebook.Publication.NavItem> pageNav = Arrays.asList(
                new com.xxcomic.ebook.Publication.NavItem("Page 1", "p1.xhtml", 0, null),
                new com.xxcomic.ebook.Publication.NavItem("Page 2", "p2.xhtml", 1, null),
                new com.xxcomic.ebook.Publication.NavItem("Page 3", "p3.xhtml", 2, null)
        );
        assertTrue(com.xxcomic.ebook.Publication.isPseudoPageNav(pageNav, 3));

        // Pseudo-page list with bare numbers
        List<com.xxcomic.ebook.Publication.NavItem> numNav = Arrays.asList(
                new com.xxcomic.ebook.Publication.NavItem("001", "p1.xhtml", 0, null),
                new com.xxcomic.ebook.Publication.NavItem("002", "p2.xhtml", 1, null)
        );
        assertTrue(com.xxcomic.ebook.Publication.isPseudoPageNav(numNav, 2));

        // Real chapter list (should NOT be detected as pseudo-page)
        List<com.xxcomic.ebook.Publication.NavItem> realChapters = Arrays.asList(
                new com.xxcomic.ebook.Publication.NavItem("第一话：相遇", "c1.xhtml", 0, null),
                new com.xxcomic.ebook.Publication.NavItem("第二话：羁绊", "c2.xhtml", 20, null),
                new com.xxcomic.ebook.Publication.NavItem("第三话：决战", "c3.xhtml", 40, null)
        );
        assertFalse(com.xxcomic.ebook.Publication.isPseudoPageNav(realChapters, 60));
    }
}
