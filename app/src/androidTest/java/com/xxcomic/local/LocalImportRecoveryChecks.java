package com.xxcomic.local;

import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Collections;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/** Runs only in the explicitly selected test environment, never against the user's library. */
public final class LocalImportRecoveryChecks {
    public static int run(Context context) throws Exception {
        File root = new File(context.getCacheDir(), "local_native_checks_" + System.nanoTime());
        LocalStorageManager storage = new LocalStorageManager(root);
        File db = new File(root, "checks.db");
        LocalLibraryStore store = new LocalLibraryStore(context, db);
        int checks = 0;
        try {
            byte[] png;
            Bitmap bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888);
            try (ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes);
                png = bytes.toByteArray();
            } finally { bitmap.recycle(); }
            File archive = new File(root, "original.cbz");
            byte[] fake = new byte[128];
            fake[0] = (byte) 255; fake[1] = (byte) 216; fake[2] = (byte) 255;
            try (ZipOutputStream out = new ZipOutputStream(new FileOutputStream(archive))) {
                entry(out, "1.jpg", fake);
                entry(out, "2.png", png);
                entry(out, "10.gif", android.util.Base64.decode(
                        "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", android.util.Base64.DEFAULT));
            }
            ArchiveIndex.ParseResult indexed = ArchiveIndex.indexArchive(archive, "native");
            require(indexed.totalPages == 2 && "2.png".equals(indexed.firstValidPageEntry), "native codec rejects bad first page and keeps small GIF");
            checks++;

            LocalImporter importer = new LocalImporter(context, storage, store);
            LocalModels.Book imported = importer.importArchiveUri(Uri.fromFile(archive), "original.cbz", null);
            LocalModels.Book duplicate = importer.importArchiveUri(Uri.fromFile(archive), "another-name.cbz", null);
            require(imported.id.equals(duplicate.id) && store.getBookCount() == 1, "real importer duplicate detection");
            String chapter = store.getChapters(imported.id).get(0).id;
            String page = store.getPages(chapter).get(0).id;
            store.renameBook(imported.id, "保留的名字");
            new LocalContentResolver(store, storage).materializePage(page);
            require(store.deleteBook(imported.id, storage), "delete completes");
            require(archive.exists(), "original SAF source preserved");
            LocalModels.Book reimport = importer.importArchiveUri(Uri.fromFile(archive), "changed-name.cbz", null);
            require(imported.id.equals(reimport.id) && "保留的名字".equals(reimport.getDisplayTitle()), "real reimport identity/title");
            require(chapter.equals(store.getChapters(reimport.id).get(0).id)
                    && page.equals(store.getPages(chapter).get(0).id), "reimport chapter/page identity");
            checks++;

            // Persist a move-before-ready state, close/reopen the real SQLite database, then recover files.
            LocalModels.Book pending = new LocalModels.Book("local_pending", "pending_fp", "Pending", null,
                    "zip", "import", "local_pending", "pending.zip", null, 3, 0, 0, LocalModels.STATUS_STAGING, 0, 0);
            store.commitImport(pending, Collections.emptyList(), Collections.emptyMap());
            write(storage.getBookImportFile(pending.relativePath), new byte[]{1, 2, 3});
            write(storage.createStagingFile("interrupted_", ".tmp"), new byte[]{4});
            store.close();
            store = new LocalLibraryStore(context, db);
            store.recoverOrphanedStates(storage);
            require(store.getBook(pending.id) == null && !storage.getBookImportFile(pending.relativePath).exists(), "restart recovers pending publication");
            require(storage.getStagingDir().list().length == 0 && store.getBook(reimport.id) != null, "recovery preserves ready content");
            checks++;

            LocalStorageManager failingStorage = new LocalStorageManager(root) {
                @Override public synchronized boolean clearDerivedPagesForBook(String id) { return false; }
            };
            require(!store.deleteBook(reimport.id, failingStorage), "failed cleanup not reported successful");
            require(LocalModels.STATUS_DELETING.equals(store.getBook(reimport.id).status), "deleting state retained");
            store.close();
            store = new LocalLibraryStore(context, db);
            store.recoverOrphanedStates(storage);
            require(store.getBook(reimport.id) == null && store.findDeletedByFingerprint(reimport.fingerprint) != null, "retry after restart completes tombstone");
            checks++;

            // Real SQLite staging transaction, injected ready-commit failure; original and tombstone survive.
            store.close();
            store = new LocalLibraryStore(context, db) {
                @Override public synchronized void commitImport(LocalModels.Book book, java.util.List<LocalModels.Chapter> chapters,
                        java.util.Map<String, java.util.List<LocalModels.Page>> pages) {
                    if (LocalModels.STATUS_READY.equals(book.status)) throw new android.database.SQLException("injected ready failure");
                    super.commitImport(book, chapters, pages);
                }
            };
            try {
                new LocalImporter(context, storage, store).importArchiveUri(Uri.fromFile(archive), "original.cbz", null);
                throw new AssertionError("failed database commit accepted");
            } catch (android.database.SQLException expected) { }
            require(store.getBookCount() == 0 && storage.getImportsTotalSize() == 0, "failed import rolled back files and ready book");
            require(store.findDeletedByFingerprint(imported.fingerprint) != null && archive.exists(), "failed reimport preserves tombstone and original");
            checks++;
            return checks;
        } finally {
            store.close();
            storage.deleteRecursively(root);
        }
    }

    private static void entry(ZipOutputStream out, String path, byte[] bytes) throws IOException {
        out.putNextEntry(new ZipEntry(path)); out.write(bytes); out.closeEntry();
    }

    private static void write(File file, byte[] bytes) throws IOException {
        try (FileOutputStream out = new FileOutputStream(file)) { out.write(bytes); }
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
