package com.xxcomic.local;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class LocalStorageManagerTest {
    @Test public void downloadDeletionAndCacheCleanupCannotDeleteImports() throws Exception {
        File imported=storageManager.getBookImportFile("original.cbz");
        Files.write(imported.toPath(),new byte[]{1,2});
        File downloaded=storageManager.getDownloadFile("book/ch/0.img");
        assertTrue(downloaded.getParentFile().mkdirs());Files.write(downloaded.toPath(),new byte[]{3,4});
        storageManager.clearDerivedPagesCache();assertTrue(downloaded.isFile());assertTrue(imported.isFile());
        LocalModels.Book book=new LocalModels.Book("book","book","title",null,"folder","download","online-key","book",null,2,1,1,"ready",0,0);
        assertTrue(storageManager.deleteBookFiles(book));assertFalse(downloaded.exists());assertTrue(imported.isFile());
    }
    @Test public void downloadPathsRejectRootAndTraversal() throws Exception {
        org.junit.Assert.assertThrows(IOException.class,()->storageManager.getDownloadFile(""));
        org.junit.Assert.assertThrows(IOException.class,()->storageManager.getDownloadFile("."));
        org.junit.Assert.assertThrows(SecurityException.class,()->storageManager.getDownloadFile("../imports/a"));
    }
    @Test
    public void rejectsImportRootAsBookPath() throws Exception {
        try { storageManager.getBookImportFile(""); org.junit.Assert.fail("accepted imports root as one book"); }
        catch (IOException | SecurityException expected) { }
    }

    @Test
    public void bookDeletionReportsDerivedFailure() throws Exception {
        LocalStorageManager failing = new LocalStorageManager(tempRoot) {
            @Override public synchronized boolean clearDerivedPagesForBook(String id) { return false; }
        };
        LocalModels.Book book = new LocalModels.Book("book", "fp", "title", null, "zip", "import", "book",
                "book.zip", null, 0, 1, 1, LocalModels.STATUS_DELETING, 0, 0);
        assertFalse(failing.deleteBookFiles(book));
    }
    private File tempRoot;
    private LocalStorageManager storageManager;

    @Before
    public void setUp() throws IOException {
        tempRoot = Files.createTempDirectory("local_storage_test").toFile();
        storageManager = new LocalStorageManager(tempRoot);
    }

    @After
    public void tearDown() {
        if (tempRoot != null && tempRoot.exists()) {
            storageManager.deleteRecursively(tempRoot);
        }
    }

    @Test
    public void testDirectoryInitialization() {
        assertTrue(storageManager.getLibraryRoot().exists());
        assertTrue(storageManager.getImportsDir().exists());
        assertTrue(storageManager.getStagingDir().exists());
        assertTrue(storageManager.getDerivedDir().exists());
        assertTrue(storageManager.getCoversDir().exists());
        assertTrue(storageManager.getPagesCacheDir().exists());
    }

    @Test
    public void testPromoteStagingToImports() throws IOException {
        File stagingFile = storageManager.createStagingFile("test_", ".zip");
        try (FileOutputStream out = new FileOutputStream(stagingFile)) {
            out.write("fake zip content".getBytes());
        }
        assertTrue(stagingFile.exists());

        File targetImportFile = storageManager.getBookImportFile("test_book.zip");
        boolean success = storageManager.promoteStagingToImports(stagingFile, targetImportFile);
        assertTrue(success);
        assertTrue(targetImportFile.exists());
        assertFalse(stagingFile.exists());
        assertEquals("fake zip content".length(), targetImportFile.length());
    }

    @Test
    public void testCleanStagingAndDerived() throws IOException {
        File stagingFile = storageManager.createStagingFile("stage_", ".tmp");
        assertTrue(stagingFile.exists());
        storageManager.cleanStaging();
        assertFalse(stagingFile.exists());

        File pageCache = new File(storageManager.getPagesCacheDir(), "page_1.tmp");
        try (FileOutputStream out = new FileOutputStream(pageCache)) {
            out.write(123);
        }
        assertTrue(pageCache.exists());
        storageManager.clearDerivedPagesCache();
        assertFalse(pageCache.exists());
    }

    @Test(expected = SecurityException.class)
    public void testPathTraversalRejection() throws IOException {
        LocalStorageManager.assertPathInsideRoot(new File(storageManager.getImportsDir(), "../../outside.txt"),
                storageManager.getImportsDir());
    }

    @Test
    public void testUsableMarginChecks() {
        // hasUsableMargin requires at least 256MiB
        boolean marginOk = storageManager.hasUsableMargin();
        long usable = storageManager.getUsableSpace();
        assertEquals(usable >= LocalStorageManager.MIN_RESERVED_FREE_BYTES, marginOk);

        // hasSufficientSpaceForRemaining(remainingBytes)
        boolean hasHugeSpace = storageManager.hasSufficientSpaceForRemaining(Long.MAX_VALUE / 2);
        assertFalse(hasHugeSpace);

        boolean hasZeroRemaining = storageManager.hasSufficientSpaceForRemaining(0);
        assertEquals(marginOk, hasZeroRemaining);
    }

    @Test
    public void testClearDerivedPagesForBook() throws IOException {
        File pagesDir = storageManager.getPagesCacheDir();
        File book1Dir = new File(pagesDir, "book_1");
        File book2Dir = new File(pagesDir, "book_2");
        book1Dir.mkdirs();
        book2Dir.mkdirs();

        File p1 = new File(book1Dir, "p1.jpg");
        File p2 = new File(book2Dir, "p2.jpg");
        try (FileOutputStream out = new FileOutputStream(p1)) { out.write(1); }
        try (FileOutputStream out = new FileOutputStream(p2)) { out.write(2); }

        assertTrue(p1.exists());
        assertTrue(p2.exists());

        storageManager.clearDerivedPagesForBook("book_1");

        assertFalse(p1.exists());
        assertFalse(book1Dir.exists());
        assertTrue(p2.exists());
        assertTrue(book2Dir.exists());
    }

    @Test
    public void testEnforcePagesCacheLimit() throws IOException {
        File pagesDir = storageManager.getPagesCacheDir();
        File bDir = new File(pagesDir, "book_cache");
        bDir.mkdirs();

        File oldFile = new File(bDir, "old.jpg");
        File newFile = new File(bDir, "new.jpg");

        byte[] chunk = new byte[1024]; // 1 KB
        try (FileOutputStream out = new FileOutputStream(oldFile)) { out.write(chunk); }
        try (FileOutputStream out = new FileOutputStream(newFile)) { out.write(chunk); }

        oldFile.setLastModified(System.currentTimeMillis() - 100000);
        newFile.setLastModified(System.currentTimeMillis());

        // Trim cache so total size is <= 1500 bytes (should delete oldFile of 1024 bytes)
        storageManager.enforcePagesCacheLimit(1500);

        assertFalse(oldFile.exists());
        assertTrue(newFile.exists());
    }

    @Test
    public void testCleanupOrphans() throws IOException {
        // Create active book file and orphan book file
        File activeImport = new File(storageManager.getImportsDir(), "active.zip");
        File orphanImport = new File(storageManager.getImportsDir(), "orphan.zip");
        try (FileOutputStream out = new FileOutputStream(activeImport)) { out.write("active".getBytes()); }
        try (FileOutputStream out = new FileOutputStream(orphanImport)) { out.write("orphan".getBytes()); }

        // Create active cover and orphan cover
        File activeCover = new File(storageManager.getCoversDir(), "cover_active.jpg");
        File orphanCover = new File(storageManager.getCoversDir(), "cover_orphan.jpg");
        try (FileOutputStream out = new FileOutputStream(activeCover)) { out.write("active cover".getBytes()); }
        try (FileOutputStream out = new FileOutputStream(orphanCover)) { out.write("orphan cover".getBytes()); }

        java.util.Set<String> activeRelativePaths = new java.util.HashSet<>();
        activeRelativePaths.add("active.zip");

        java.util.Set<String> activeCoverPaths = new java.util.HashSet<>();
        activeCoverPaths.add(activeCover.getAbsolutePath());

        storageManager.cleanupOrphans(activeRelativePaths, activeCoverPaths);

        assertTrue(activeImport.exists());
        assertFalse(orphanImport.exists());

        assertTrue(activeCover.exists());
        assertFalse(orphanCover.exists());
    }

    @Test
    public void testEnforcePagesCacheLimitPreservesActiveWritingFiles() throws IOException {
        File pagesDir = storageManager.getPagesCacheDir();
        File bDir = new File(pagesDir, "book_writing_test");
        bDir.mkdirs();

        File writingFile = new File(bDir, "page1_123.writing");
        File tmpWritingFile = new File(bDir, "page2_456.tmp.writing");
        File finishedFile = new File(bDir, "finished.jpg");

        byte[] chunk = new byte[1024]; // 1 KB
        try (FileOutputStream out = new FileOutputStream(writingFile)) { out.write(chunk); }
        try (FileOutputStream out = new FileOutputStream(tmpWritingFile)) { out.write(chunk); }
        try (FileOutputStream out = new FileOutputStream(finishedFile)) { out.write(chunk); }

        // Make writing files older than finished file
        writingFile.setLastModified(System.currentTimeMillis() - 100000);
        tmpWritingFile.setLastModified(System.currentTimeMillis() - 90000);
        finishedFile.setLastModified(System.currentTimeMillis());

        // Trim cache so total size must be <= 500 bytes (finishedFile of 1024 bytes should be deleted)
        storageManager.enforcePagesCacheLimit(500);

        // Active writing files must NOT be collected or deleted by cache eviction
        assertTrue(writingFile.exists());
        assertTrue(tmpWritingFile.exists());
        assertFalse(finishedFile.exists());
    }

    @Test
    public void testExternalFileZeroCopyProtectionDuringDeletion() throws IOException {
        File externalSource = new File(tempRoot, "user_downloaded_manga.cbz");
        Files.write(externalSource.toPath(), new byte[]{1, 2, 3, 4, 5});
        assertTrue(externalSource.exists());

        LocalModels.Book mappedBook = new LocalModels.Book(
                "external_book", "fp_ext", "External Comic", null,
                LocalModels.FORMAT_CBZ, LocalModels.SOURCE_TYPE_IMPORT, "external_book",
                externalSource.getAbsolutePath(), null, 5, 1, 1,
                LocalModels.STATUS_READY, System.currentTimeMillis(), System.currentTimeMillis()
        );

        File resolved = storageManager.getBookContentFile(mappedBook);
        assertEquals(externalSource.getCanonicalPath(), resolved.getCanonicalPath());

        // Deleting the book from bookshelf must NOT delete the user's source file!
        assertTrue(storageManager.deleteBookFiles(mappedBook));
        assertTrue("External source file must remain intact after book deletion!", externalSource.exists());
        assertEquals(5, externalSource.length());
    }
}
