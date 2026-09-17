package com.xxcomic.local;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class LocalContentResolverTest {
    @Test
    public void testSchemeAndUrlParsing() {
        String pageUrl = LocalContentResolver.buildPageUrl("page_123");
        assertEquals("local://page/page_123", pageUrl);
        assertTrue(LocalContentResolver.isLocalUrl(pageUrl));
        assertTrue(LocalContentResolver.isLocalPageUrl(pageUrl));
        assertFalse(LocalContentResolver.isLocalCoverUrl(pageUrl));
        assertEquals("page_123", LocalContentResolver.extractId(pageUrl, LocalContentResolver.PREFIX_PAGE));

        String coverUrl = LocalContentResolver.buildCoverUrl("book_456");
        assertEquals("local://cover/book_456", coverUrl);
        assertTrue(LocalContentResolver.isLocalUrl(coverUrl));
        assertTrue(LocalContentResolver.isLocalCoverUrl(coverUrl));
        assertFalse(LocalContentResolver.isLocalPageUrl(coverUrl));
        assertEquals("book_456", LocalContentResolver.extractId(coverUrl, LocalContentResolver.PREFIX_COVER));

        String chapterUrl = LocalContentResolver.buildChapterUrl("chap_789");
        assertEquals("local://chapter/chap_789", chapterUrl);
        assertTrue(LocalContentResolver.isLocalUrl(chapterUrl));
        assertTrue(LocalContentResolver.isLocalChapterUrl(chapterUrl));
        assertEquals("chap_789", LocalContentResolver.extractId(chapterUrl, LocalContentResolver.PREFIX_CHAPTER));

        assertFalse(LocalContentResolver.isLocalUrl("https://example.com/image.jpg"));
        assertFalse(LocalContentResolver.isLocalUrl(null));
        assertFalse(LocalContentResolver.isLocalUrl(""));
    }

    @Test
    public void testPageLocksSupportApi23ConcurrentResolution() throws Exception {
        LocalContentResolver resolver = new LocalContentResolver(new FakeStore(), null);
        int threadCount = 16;
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newFixedThreadPool(threadCount);
        java.util.concurrent.CountDownLatch readyLatch = new java.util.concurrent.CountDownLatch(threadCount);
        java.util.concurrent.CountDownLatch startLatch = new java.util.concurrent.CountDownLatch(1);
        java.util.List<Object> locks = java.util.Collections.synchronizedList(new java.util.ArrayList<>());

        for (int i = 0; i < threadCount; i++) {
            executor.submit(() -> {
                readyLatch.countDown();
                try {
                    startLatch.await();
                    Object lock = resolver.getPageLock("test_page_api23");
                    locks.add(lock);
                } catch (InterruptedException ignored) {}
            });
        }

        readyLatch.await();
        startLatch.countDown();
        executor.shutdown();
        executor.awaitTermination(3, java.util.concurrent.TimeUnit.SECONDS);

        assertEquals(threadCount, locks.size());
        Object firstLock = locks.get(0);
        assertNotNull(firstLock);
        for (Object lock : locks) {
            org.junit.Assert.assertSame(firstLock, lock);
        }
    }

    @Test
    public void testMaterializePageBlocksDeletingBook() throws Exception {
        FakeStore fakeStore = new FakeStore();
        java.io.File tempRoot = java.nio.file.Files.createTempDirectory("resolver_test").toFile();
        try {
            LocalStorageManager storage = new LocalStorageManager(tempRoot);
            LocalContentResolver resolver = new LocalContentResolver(fakeStore, storage);

            String bookId = "book_deleting_1";
            LocalModels.Book book = new LocalModels.Book(
                    bookId, "fp_deleting", "Deleting Comic", null,
                    LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, bookId,
                    "imports/del.zip", null, 1000L, 1, 1,
                    LocalModels.STATUS_DELETING, System.currentTimeMillis(), System.currentTimeMillis()
            );
            LocalModels.Page page = new LocalModels.Page("p_del", bookId, "ch1", 0, "01.png", 100, 100, null, "image/png");

            fakeStore.books.put(bookId, book);
            fakeStore.pages.put(page.id, page);

            try {
                resolver.materializePage(page.id);
                org.junit.Assert.fail("Expected IOException when book is in deleting state");
            } catch (java.io.IOException e) {
                assertTrue(e.getMessage().contains("删除中"));
            }
        } finally {
            deleteRecursive(tempRoot);
        }
    }

    @Test
    public void testMaterializePageEnforcesSizeBudgetAndCleansWritingFile() throws Exception {
        FakeStore fakeStore = new FakeStore();
        java.io.File tempRoot = java.nio.file.Files.createTempDirectory("resolver_budget_test").toFile();
        try {
            LocalStorageManager storage = new LocalStorageManager(tempRoot);
            LocalContentResolver resolver = new LocalContentResolver(fakeStore, storage);

            String bookId = "book_big_zip";
            String relPath = bookId + ".zip";
            java.io.File zipFile = storage.getBookImportFile(relPath);
            zipFile.getParentFile().mkdirs();

            // Create a zip with an entry whose uncompressed size exceeds 32MiB
            try (java.util.zip.ZipOutputStream zos = new java.util.zip.ZipOutputStream(new java.io.FileOutputStream(zipFile))) {
                zos.putNextEntry(new java.util.zip.ZipEntry("huge.png"));
                byte[] chunk = new byte[65536];
                // Write 33 MiB of data
                for (int i = 0; i < (33 * 1024 * 1024 / chunk.length); i++) {
                    zos.write(chunk);
                }
                zos.closeEntry();
            }

            LocalModels.Book book = new LocalModels.Book(
                    bookId, "fp_huge", "Huge Zip", null,
                    LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, bookId,
                    relPath, null, zipFile.length(), 1, 1,
                    LocalModels.STATUS_READY, System.currentTimeMillis(), System.currentTimeMillis()
            );
            LocalModels.Page page = new LocalModels.Page("p_huge", bookId, "ch1", 0, "huge.png", 100, 100, null, "image/png");

            fakeStore.books.put(bookId, book);
            fakeStore.pages.put(page.id, page);

            try {
                resolver.materializePage(page.id);
                org.junit.Assert.fail("Expected IOException for page exceeding 32MiB size limit");
            } catch (java.io.IOException e) {
                assertTrue(e.getMessage().contains("32MiB") || e.getMessage().contains("超出安全限制"));
            }

            // Verify .writing file was deleted on failure
            java.io.File bookCacheDir = new java.io.File(storage.getPagesCacheDir(), bookId);
            if (bookCacheDir.exists()) {
                java.io.File[] files = bookCacheDir.listFiles();
                if (files != null) {
                    for (java.io.File f : files) {
                        assertFalse(f.getName().endsWith(".writing"));
                    }
                }
            }
        } finally {
            deleteRecursive(tempRoot);
        }
    }

    private static class FakeStore extends LocalLibraryStore {
        final java.util.Map<String, LocalModels.Book> books = new java.util.HashMap<>();
        final java.util.Map<String, LocalModels.Page> pages = new java.util.HashMap<>();

        FakeStore() {
            super();
        }

        @Override
        public synchronized LocalModels.Book getBook(String bookId) {
            return books.get(bookId);
        }

        @Override
        public synchronized LocalModels.Page getPage(String pageId) {
            return pages.get(pageId);
        }
    }

    private static void deleteRecursive(java.io.File file) {
        if (file.isDirectory()) {
            java.io.File[] children = file.listFiles();
            if (children != null) {
                for (java.io.File child : children) deleteRecursive(child);
            }
        }
        file.delete();
    }
}
