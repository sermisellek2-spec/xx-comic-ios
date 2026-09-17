package com.xxcomic.local;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class ArchiveIndexTest {
    private File tempDir;
    // Minimal valid 1x1 PNG bytes (starts with 89 50 4E 47 ...)
    private static final byte[] FAKE_PNG_BYTES = new byte[]{
            (byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 'I', 'H', 'D', 'R'
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
            addZipEntry(zos, "10.png", FAKE_PNG_BYTES);
            addZipEntry(zos, "1.png", FAKE_PNG_BYTES);
            addZipEntry(zos, "2.png", FAKE_PNG_BYTES);
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
            addZipEntry(zos, "第10话/01.png", FAKE_PNG_BYTES);
            addZipEntry(zos, "第2话/01.png", FAKE_PNG_BYTES);
            addZipEntry(zos, "第2话/02.png", FAKE_PNG_BYTES);
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
            addZipEntry(zos, "ComicOuterFolder/第1话/01.png", FAKE_PNG_BYTES);
            addZipEntry(zos, "ComicOuterFolder/第2话/01.png", FAKE_PNG_BYTES);
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
            addZipEntry(zos, "cover.png", FAKE_PNG_BYTES);
            addZipEntry(zos, "第1话/01.png", FAKE_PNG_BYTES);
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
            addZipEntry(zos, "01.png", FAKE_PNG_BYTES);
        }

        ArchiveIndex.ParseResult result = ArchiveIndex.indexArchive(zip, "book5");
        assertEquals(1, result.totalPages);
        assertEquals("01.png", result.firstValidPageEntry);
    }

    @Test(expected = IOException.class)
    public void testRejectsFakeImageExtension() throws IOException {
        File zip = new File(tempDir, "fake.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            // Text content pretending to be jpg
            addZipEntry(zos, "01.jpg", "This is plain text not an image".getBytes());
        }

        ArchiveIndex.indexArchive(zip, "book6");
    }

    @Test(expected = SecurityException.class)
    public void testRejectsPathTraversal() throws IOException {
        File zip = new File(tempDir, "evil.zip");
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zip))) {
            addZipEntry(zos, "../evil.png", FAKE_PNG_BYTES);
        }

        ArchiveIndex.indexArchive(zip, "book7");
    }

    private void addZipEntry(ZipOutputStream zos, String name, byte[] data) throws IOException {
        ZipEntry entry = new ZipEntry(name);
        zos.putNextEntry(entry);
        zos.write(data);
        zos.closeEntry();
    }
}
