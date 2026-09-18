package com.xxcomic.local;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public class LocalContentResolverTest {
    @Test public void folderVolumeKeepsItsPathAfterAnotherVolumeBecomesFirst() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("folder_volume").toFile();
        LocalStorageManager storage = new LocalStorageManager(root);
        LocalModels.Book ready = book(LocalModels.STATUS_READY);
        index.books.put(ready.id, ready);
        try {
            java.io.File directory = storage.getBookImportFile("original-images");
            assertTrue(directory.mkdir());
            java.io.File image = new java.io.File(directory, "1.png");
            java.nio.file.Files.write(image.toPath(), new byte[]{7, 8, 9});
            index.volumes.put("folder", new LocalModels.Volume("folder", ready.id, "fp", "原图片卷",
                    "folder", "original-images", 3, 1, "ready", 0, 0));
            index.pages.put("p", new LocalModels.Page("p", ready.id, "folder", "ch", 0, "1.png", 1, 1, null, "image/png"));
            LocalContentResolver resolver = new LocalContentResolver(index, storage);
            try (java.io.InputStream in = resolver.openPage("p")) { assertEquals(7, in.read()); }
            assertEquals(image.getCanonicalPath(), resolver.materializePage("p").getCanonicalPath());
        } finally { deleteRecursive(root); }
    }
    @Test
    public void mixedVolumesReadTheirOwnContainerRatherThanBookFormat() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("mixed_volumes").toFile();
        LocalStorageManager storage = new LocalStorageManager(root);
        LocalModels.Book ready = book(LocalModels.STATUS_READY);
        index.books.put(ready.id, ready);
        try {
            for (int i = 1; i <= 2; i++) {
                String id = "volume" + i;
                String format = i == 1 ? "epub" : "mobi";
                index.volumes.put(id, new LocalModels.Volume(id, ready.id, "hash" + i, id,
                        format, id + "." + format, 10, i, "ready", 0, 0));
                index.pages.put("p" + i, new LocalModels.Page("p" + i, ready.id, id,
                        "ch" + i, 0, "1.png", 1, 1, null, "image/png"));
                java.io.File archive = i == 1 ? storage.getBookImportFile("volume1.epub")
                        : storage.getDerivedBookFile("volume2", ".epub");
                try (java.util.zip.ZipOutputStream out = new java.util.zip.ZipOutputStream(new java.io.FileOutputStream(archive))) {
                    out.putNextEntry(new java.util.zip.ZipEntry("1.png"));
                    out.write(i);
                    out.closeEntry();
                }
            }
            LocalContentResolver resolver = new LocalContentResolver(index, storage);
            try (java.io.InputStream in = resolver.openPage("p1")) { assertEquals(1, in.read()); }
            try (java.io.InputStream in = resolver.openPage("p2")) { assertEquals(2, in.read()); }
        } finally { deleteRecursive(root); }
    }

    @Test
    public void missingVolumeMustNotFallBackToAnotherVolumesFile() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("missing_volume").toFile();
        LocalModels.Book ready = book(LocalModels.STATUS_READY);
        index.books.put(ready.id, ready);
        index.pages.put("p", new LocalModels.Page("p", ready.id, "missing", "ch", 0, "1.png", 1, 1, null, "image/png"));
        try {
            new LocalContentResolver(index, new LocalStorageManager(root)).openPage("p");
            org.junit.Assert.fail("missing volume accepted");
        } catch (java.io.IOException expected) {
            assertTrue(expected.getMessage().contains("分卷"));
        } finally { deleteRecursive(root); }
    }
    @Test
    public void pendingBookCannotBeOpenedEvenWhenItsArchiveExists() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("pending_page").toFile();
        LocalStorageManager storage = new LocalStorageManager(root);
        LocalModels.Book pending = book(LocalModels.STATUS_STAGING);
        index.books.put(pending.id, pending);
        index.pages.put("page", new LocalModels.Page("page", pending.id, "chapter", 0, "1.png", 1, 1, null, "image/png"));
        try {
            try (java.util.zip.ZipOutputStream out = new java.util.zip.ZipOutputStream(
                    new java.io.FileOutputStream(storage.getBookImportFile(pending.relativePath)))) {
                out.putNextEntry(new java.util.zip.ZipEntry("1.png"));
                out.write(new byte[]{1, 2, 3});
                out.closeEntry();
            }
            try (java.io.InputStream ignored = new LocalContentResolver(index, storage).openPage("page")) {
                org.junit.Assert.fail("pending book was readable");
            } catch (java.io.IOException expected) {
                assertTrue(expected.getMessage().contains("所属本地漫画"));
            }
        } finally { deleteRecursive(root); }
    }

    @Test
    public void deletionDuringMaterializationCannotPublishPage() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("delete_during_page").toFile();
        LocalStorageManager storage = new LocalStorageManager(root);
        LocalModels.Book ready = book(LocalModels.STATUS_READY);
        index.books.put(ready.id, ready);
        index.pages.put("page", new LocalModels.Page("page", ready.id, "chapter", 0, "1.png", 1, 1, null, "image/png"));
        LocalContentResolver resolver = new LocalContentResolver(index, storage) {
            @Override public java.io.InputStream openPage(String id) {
                index.books.put(ready.id, book(LocalModels.STATUS_DELETING));
                return new java.io.ByteArrayInputStream(new byte[]{1, 2, 3});
            }
        };
        try {
            try { resolver.materializePage("page"); org.junit.Assert.fail("published a deleting book"); }
            catch (java.io.IOException expected) { /* cancellation is surfaced */ }
            assertEquals(0, storage.getDerivedTotalSize());
        } finally { deleteRecursive(root); }
    }

    @Test
    public void materializationRechecksFreeSpaceDuringCopy() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("space_during_page").toFile();
        LocalStorageManager storage = new LocalStorageManager(root) {
            int checks;
            @Override public long getUsableSpace() {
                return ++checks == 1 ? 1024L * 1024 * 1024 : 0;
            }
        };
        LocalModels.Book ready = book(LocalModels.STATUS_READY);
        index.books.put(ready.id, ready);
        index.pages.put("page", new LocalModels.Page("page", ready.id, "chapter", 0, "1.png", 1, 1, null, "image/png"));
        LocalContentResolver resolver = new LocalContentResolver(index, storage) {
            @Override public java.io.InputStream openPage(String id) {
                return new java.io.ByteArrayInputStream(new byte[128 * 1024]);
            }
        };
        try {
            try { resolver.materializePage("page"); org.junit.Assert.fail("ignored disk exhaustion"); }
            catch (java.io.IOException expected) { assertTrue(expected.getMessage().contains("空间")); }
            assertEquals(0, storage.getDerivedTotalSize());
        } finally { deleteRecursive(root); }
    }

    private static LocalModels.Book book(String status) {
        return new LocalModels.Book("local_book", "fingerprint", "Comic", null,
                LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "local_book", "book.zip",
                null, 3, 1, 1, status, 0, 0);
    }
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
    public void concurrentRequestsPublishOnlyOneCompletePage() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("parallel_pages").toFile();
        LocalStorageManager storage = new LocalStorageManager(root);
        index.books.put("local_book", book(LocalModels.STATUS_READY));
        index.pages.put("page", new LocalModels.Page("page", "local_book", "chapter", 0, "1.png", 1, 1, null, "image/png"));
        java.util.concurrent.atomic.AtomicInteger reads = new java.util.concurrent.atomic.AtomicInteger();
        LocalContentResolver resolver = new LocalContentResolver(index, storage) {
            @Override public java.io.InputStream openPage(String id) {
                reads.incrementAndGet();
                return new java.io.ByteArrayInputStream(new byte[]{1, 2, 3});
            }
        };
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newFixedThreadPool(4);
        try {
            java.util.List<java.util.concurrent.Future<java.io.File>> results = new java.util.ArrayList<>();
            for (int i = 0; i < 16; i++) results.add(executor.submit(() -> resolver.materializePage("page")));
            for (java.util.concurrent.Future<java.io.File> result : results) {
                org.junit.Assert.assertArrayEquals(new byte[]{1, 2, 3}, java.nio.file.Files.readAllBytes(
                        result.get(3, java.util.concurrent.TimeUnit.SECONDS).toPath()));
            }
            assertEquals(1, reads.get());
        } finally { executor.shutdownNow(); deleteRecursive(root); }
    }

    @Test
    public void clearingCacheWaitsUntilPageConsumerFinishes() throws Exception {
        FakeStore index = new FakeStore();
        java.io.File root = java.nio.file.Files.createTempDirectory("leased_page").toFile();
        LocalStorageManager storage = new LocalStorageManager(root);
        index.books.put("local_book", book(LocalModels.STATUS_READY));
        index.pages.put("page", new LocalModels.Page("page", "local_book", "chapter", 0, "1.png", 1, 1, null, "image/png"));
        LocalContentResolver resolver = new LocalContentResolver(index, storage) {
            @Override public java.io.InputStream openPage(String id) {
                return new java.io.ByteArrayInputStream(new byte[]{1, 2, 3});
            }
        };
        java.util.concurrent.CountDownLatch entered = new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.CountDownLatch release = new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            java.util.concurrent.Future<Boolean> reading = executor.submit(() -> resolver.withPageFile("page", file -> {
                entered.countDown();
                try { if (!release.await(3, java.util.concurrent.TimeUnit.SECONDS)) throw new java.io.IOException("timeout"); }
                catch (InterruptedException e) { throw new java.io.IOException(e); }
                return file.exists() && file.length() == 3;
            }));
            assertTrue(entered.await(3, java.util.concurrent.TimeUnit.SECONDS));
            java.util.concurrent.Future<?> clearing = executor.submit(storage::clearDerivedPagesCache);
            try { clearing.get(100, java.util.concurrent.TimeUnit.MILLISECONDS); org.junit.Assert.fail("deleted page during decode"); }
            catch (java.util.concurrent.TimeoutException expected) { }
            release.countDown();
            assertTrue(reading.get(3, java.util.concurrent.TimeUnit.SECONDS));
            clearing.get(3, java.util.concurrent.TimeUnit.SECONDS);
            assertEquals(0, storage.getDerivedTotalSize());
        } finally { release.countDown(); executor.shutdownNow(); deleteRecursive(root); }
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

            // Create a zip with an entry whose uncompressed size exceeds 128MiB
            try (java.util.zip.ZipOutputStream zos = new java.util.zip.ZipOutputStream(new java.io.FileOutputStream(zipFile))) {
                zos.putNextEntry(new java.util.zip.ZipEntry("huge.png"));
                byte[] chunk = new byte[65536];
                // Write 129 MiB of data
                for (int i = 0; i < (129 * 1024 * 1024 / chunk.length); i++) {
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
                org.junit.Assert.fail("Expected IOException for page exceeding 128MiB size limit");
            } catch (java.io.IOException e) {
                assertTrue(e.getMessage().contains("128MiB") || e.getMessage().contains("超出安全限制"));
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

    private static class FakeStore implements LocalContentResolver.ContentIndex {
        final java.util.Map<String, LocalModels.Volume> volumes = new java.util.HashMap<>();
        public LocalModels.Volume getVolume(String id) { return volumes.get(id); }
        final java.util.Map<String, LocalModels.Book> books = new java.util.HashMap<>();
        final java.util.Map<String, LocalModels.Page> pages = new java.util.HashMap<>();
        final java.util.Map<String, LocalModels.Chapter> chapters = new java.util.HashMap<>();

        @Override public LocalModels.Page getFirstPage(String bookId) {
            for (LocalModels.Page page : pages.values()) if (bookId.equals(page.bookId)) return page;
            return null;
        }

        @Override
        public synchronized LocalModels.Book getBook(String bookId) {
            return books.get(bookId);
        }

        @Override
        public synchronized LocalModels.Page getPage(String pageId) {
            return pages.get(pageId);
        }

        @Override
        public synchronized LocalModels.Chapter getChapter(String chapterId) {
            return chapters.get(chapterId);
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
