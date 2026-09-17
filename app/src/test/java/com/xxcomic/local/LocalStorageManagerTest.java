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
}
