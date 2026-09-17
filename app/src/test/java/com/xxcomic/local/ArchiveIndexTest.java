package com.xxcomic.local;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class ArchiveIndexTest {
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

    private static final byte[] SIGNATURE_ONLY_PNG_BYTES = new byte[]{
            (byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A
    };

    @Before
    public void setUp() throws IOException {
        tempDir = Files.createTempDirectory("archive_index_test").toFile();
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

    @Test
    public void testFlatThreePages() throws IOException {
        File zip = new File(tempDir, "flat.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "10.png", VALID_PNG_BYTES);
            addZipEntry(zos, "1.png", VALID_PNG_BYTES);
            addZipEntry(zos, "2.png", VALID_PNG_BYTES);
        }

        ArchiveIndex.ParseResult result = ArchiveIndex.indexArchive(zip, "book1");
        assertEquals(1, result.chapters.size());
        assertEquals("正文", result.chapters.get(0).title);
        assertEquals(3, result.chapters.get(0).pageCount);

        // Check page order is naturally sorted: 1.png, 2.png, 10.png
        assertEquals("1.png", result.pagesByChapter.get(result.chapters.get(0).id).get(0).entryPath);
        assertEquals("2.png", result.pagesByChapter.get(result.chapters.get(0).id).get(1).entryPath);
        assertEquals("10.png", result.pagesByChapter.get(result.chapters.get(0).id).get(2).entryPath);
    }

    @Test
    public void testTwoChaptersNaturallyOrdered() throws IOException {
        File zip = new File(tempDir, "two_chapters.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "第10话/01.png", VALID_PNG_BYTES);
            addZipEntry(zos, "第2话/01.png", VALID_PNG_BYTES);
            addZipEntry(zos, "第2话/02.png", VALID_PNG_BYTES);
        }

        ArchiveIndex.ParseResult result = ArchiveIndex.indexArchive(zip, "book2");
        assertEquals(2, result.chapters.size());
        assertEquals("第2话", result.chapters.get(0).title);
        assertEquals(2, result.chapters.get(0).pageCount);
        assertEquals("第10话", result.chapters.get(1).title);
        assertEquals(1, result.chapters.get(1).pageCount);
    }

    @Test
    public void testSingleWrapperDirectoryStripped() throws IOException {
        File zip = new File(tempDir, "wrapped.cbz");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "ComicOuterFolder/第1话/01.png", VALID_PNG_BYTES);
            addZipEntry(zos, "ComicOuterFolder/第2话/01.png", VALID_PNG_BYTES);
        }

        ArchiveIndex.ParseResult result = ArchiveIndex.indexArchive(zip, "book3");
        assertEquals(2, result.chapters.size());
        assertEquals("第1话", result.chapters.get(0).title);
        assertEquals("第2话", result.chapters.get(1).title);
    }

    @Test
    public void testRootImagesWithSubfoldersCreatesUnassignedChapter() throws IOException {
        File zip = new File(tempDir, "mixed.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "cover.png", VALID_PNG_BYTES);
            addZipEntry(zos, "第1话/01.png", VALID_PNG_BYTES);
        }

        ArchiveIndex.ParseResult result = ArchiveIndex.indexArchive(zip, "book4");
        assertEquals(2, result.chapters.size());
        assertEquals("未分章", result.chapters.get(0).title);
        assertEquals(1, result.chapters.get(0).pageCount);
        assertEquals("第1话", result.chapters.get(1).title);
        assertEquals(1, result.chapters.get(1).pageCount);
    }

    @Test
    public void testIgnoresMacOsAndDsStoreMetadata() throws IOException {
        File zip = new File(tempDir, "metadata.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "__MACOSX/._01.png", new byte[]{1, 2, 3});
            addZipEntry(zos, ".DS_Store", new byte[]{1, 2, 3});
            addZipEntry(zos, "01.png", VALID_PNG_BYTES);
        }

        ArchiveIndex.ParseResult result = ArchiveIndex.indexArchive(zip, "book5");
        assertEquals(1, result.totalPages);
        assertEquals("01.png", result.firstValidPageEntry);
    }

    @Test(expected = IOException.class)
    public void testRejectsFakeImageExtension() throws IOException {
        File zip = new File(tempDir, "fake.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "01.jpg", "This is plain text not an image".getBytes());
        }

        ArchiveIndex.indexArchive(zip, "book6");
    }

    @Test(expected = SecurityException.class)
    public void testRejectsPathTraversal() throws IOException {
        File zip = new File(tempDir, "evil.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "../evil.png", VALID_PNG_BYTES);
        }

        ArchiveIndex.indexArchive(zip, "book7");
    }

    @Test
    public void testRejectsSignatureOnlyPng() throws IOException {
        File zip = new File(tempDir, "signature_only.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "1.png", SIGNATURE_ONLY_PNG_BYTES);
        }

        try {
            ArchiveIndex.indexArchive(zip, "book_sig_only");
            fail("Expected IOException for signature-only PNG without valid dimensions");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("损坏") || e.getMessage().contains("非有效图片格式") || e.getMessage().contains("有效"));
        }
    }

    @Test
    public void testRejectsDuplicateNormalizedPaths() throws IOException {
        File zip = new File(tempDir, "duplicate_norm.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "ch1/01.png", VALID_PNG_BYTES);
            addZipEntry(zos, "ch1/./01.png", VALID_PNG_BYTES);
        }

        try {
            ArchiveIndex.indexArchive(zip, "book_dup");
            fail("Expected IOException for duplicate normalized path");
        } catch (IOException e) {
            assertTrue(e.getMessage().contains("重复"));
        }
    }

    @Test
    public void testDeterministicIdsAcrossReimport() throws IOException {
        File zip = new File(tempDir, "stable_ids.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "ch1/01.png", VALID_PNG_BYTES);
            addZipEntry(zos, "ch2/01.png", VALID_PNG_BYTES);
        }

        String stableBookId = "local_stable_fingerprint_123";
        ArchiveIndex.ParseResult result1 = ArchiveIndex.indexArchive(zip, stableBookId);
        ArchiveIndex.ParseResult result2 = ArchiveIndex.indexArchive(zip, stableBookId);

        assertEquals(result1.chapters.size(), result2.chapters.size());
        for (int i = 0; i < result1.chapters.size(); i++) {
            LocalModels.Chapter ch1 = result1.chapters.get(i);
            LocalModels.Chapter ch2 = result2.chapters.get(i);
            assertEquals(ch1.id, ch2.id);
            assertEquals(ch1.title, ch2.title);

            java.util.List<LocalModels.Page> p1 = result1.pagesByChapter.get(ch1.id);
            java.util.List<LocalModels.Page> p2 = result2.pagesByChapter.get(ch2.id);
            assertNotNull(p1);
            assertNotNull(p2);
            assertEquals(p1.size(), p2.size());
            for (int j = 0; j < p1.size(); j++) {
                assertEquals(p1.get(j).id, p2.get(j).id);
            }
        }
    }

    @Test
    public void testApi23ZipFileCompatWorks() throws IOException {
        File zip = new File(tempDir, "compat.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "01.png", VALID_PNG_BYTES);
        }

        try (ZipFile zipFile = ArchiveIndex.openZipFileCompat(zip, StandardCharsets.UTF_8)) {
            assertNotNull(zipFile);
            assertNotNull(zipFile.getEntry("01.png"));
        }
    }

    private void addZipEntry(ZipOutputStream zos, String name, byte[] data) throws IOException {
        ZipEntry entry = new ZipEntry(name);
        zos.putNextEntry(entry);
        zos.write(data);
        zos.closeEntry();
    }
}
