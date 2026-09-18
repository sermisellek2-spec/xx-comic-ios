package com.xxcomic.local;

import android.content.ContentValues;
import android.content.Context;
import android.content.ContextWrapper;
import android.database.Cursor;
import android.database.DatabaseErrorHandler;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class LocalLibraryStore implements LocalContentResolver.ContentIndex {
    private static final String DATABASE_NAME = "local_library.db";
    private static final int DATABASE_VERSION = 2;

    private static final String TABLE_BOOKS = "books";
    private static final String TABLE_DELETED_FINGERPRINTS = "deleted_fingerprints";
    private static final String TABLE_CHAPTERS = "chapters";
    private static final String TABLE_PAGES = "pages";
    private static final String TABLE_VOLUMES = "local_volumes";

    private final OpenHelper helper;

    public static final class DeletedFingerprint {
        public final String fingerprint;
        public final String progressKey;
        public final String userTitle;
        public final long deletedAt;

        public DeletedFingerprint(String fingerprint, String progressKey, String userTitle, long deletedAt) {
            this.fingerprint = fingerprint;
            this.progressKey = progressKey;
            this.userTitle = userTitle;
            this.deletedAt = deletedAt;
        }
    }

    public LocalLibraryStore(Context context) {
        this.helper = new OpenHelper(new NoBackupContext(context));
    }

    // For testing or custom database file location
    public LocalLibraryStore(Context context, File customDbFile) {
        this.helper = new OpenHelper(new CustomDirectoryContext(context, customDbFile));
    }

    public synchronized void close() {
        helper.close();
    }

    public List<LocalModels.Book> listBooks() {
        SQLiteDatabase db = helper.getReadableDatabase();
        List<LocalModels.Book> result = new ArrayList<>();
        try (Cursor c = db.query(TABLE_BOOKS, null, "status = ?",
                new String[]{LocalModels.STATUS_READY}, null, null, "created_at DESC")) {
            while (c != null && c.moveToNext()) {
                result.add(readBook(c));
            }
        }
        return result;
    }

    public int getBookCount() {
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.rawQuery("SELECT COUNT(*) FROM " + TABLE_BOOKS + " WHERE status = ?",
                new String[]{LocalModels.STATUS_READY})) {
            if (c != null && c.moveToFirst()) {
                return c.getInt(0);
            }
        } catch (Exception ignored) {}
        return 0;
    }

    public LocalModels.Book getBook(String bookId) {
        if (bookId == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_BOOKS, null, "id = ?",
                new String[]{bookId}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return readBook(c);
            }
        }
        return null;
    }

    public LocalModels.Book findReadyByFingerprint(String fingerprint) {
        if (fingerprint == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_BOOKS, null, "fingerprint = ? AND status = ? AND source_type != 'import'",
                new String[]{fingerprint, LocalModels.STATUS_READY}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return readBook(c);
            }
        }
        try (Cursor c = db.rawQuery("SELECT b.* FROM books b JOIN local_volumes v ON v.book_id=b.id "
                + "WHERE v.fingerprint=? AND v.status='ready' AND b.status='ready' LIMIT 1", new String[]{fingerprint})) {
            if (c.moveToFirst()) return readBook(c);
        }
        return null;
    }

    @Override public LocalModels.Volume getVolume(String id) {
        if (id == null) return null;
        try (Cursor c = helper.getReadableDatabase().query(TABLE_VOLUMES, null, "id=?",
                new String[]{id}, null, null, null)) {
            return c.moveToFirst() ? readVolume(c) : null;
        }
    }

    public List<LocalModels.Volume> getVolumes(String bookId) {
        List<LocalModels.Volume> result = new ArrayList<>();
        try (Cursor c = helper.getReadableDatabase().query(TABLE_VOLUMES, null, "book_id=?",
                new String[]{bookId}, null, null, "order_index, id")) {
            while (c.moveToNext()) result.add(readVolume(c));
        }
        return result;
    }

    public Map<String, Integer> getReadyVolumeCounts() {
        Map<String, Integer> counts = new java.util.HashMap<>();
        try (Cursor c = helper.getReadableDatabase().rawQuery(
                "SELECT book_id,COUNT(*) FROM local_volumes WHERE status='ready' GROUP BY book_id", null)) {
            while (c.moveToNext()) counts.put(c.getString(0), c.getInt(1));
        }
        return counts;
    }

    private static LocalModels.Volume readVolume(Cursor c) {
        return new LocalModels.Volume(c.getString(c.getColumnIndexOrThrow("id")),
                c.getString(c.getColumnIndexOrThrow("book_id")), c.getString(c.getColumnIndexOrThrow("fingerprint")),
                c.getString(c.getColumnIndexOrThrow("title")), c.getString(c.getColumnIndexOrThrow("format")),
                c.getString(c.getColumnIndexOrThrow("relative_path")), c.getLong(c.getColumnIndexOrThrow("total_size")),
                c.getInt(c.getColumnIndexOrThrow("order_index")), c.getString(c.getColumnIndexOrThrow("status")),
                c.getLong(c.getColumnIndexOrThrow("created_at")), c.getLong(c.getColumnIndexOrThrow("updated_at")));
    }

    private static void insertVolume(SQLiteDatabase db, LocalModels.Volume volume) {
        ContentValues values = new ContentValues();
        values.put("id", volume.id); values.put("book_id", volume.seriesId);
        values.put("fingerprint", volume.fingerprint.isEmpty() ? null : volume.fingerprint);
        values.put("title", volume.title); values.put("format", volume.format);
        values.put("relative_path", volume.relativePath); values.put("total_size", volume.totalSize);
        values.put("order_index", volume.orderIndex); values.put("status", volume.status);
        values.put("created_at", volume.createdAt); values.put("updated_at", volume.updatedAt);
        db.insertOrThrow(TABLE_VOLUMES, null, values);
    }

    /** Book remains the series identity; only its independently stored files need a new table. */
    private static void ensureDefaultVolume(SQLiteDatabase db, LocalModels.Book book) {
        if (!LocalModels.SOURCE_TYPE_IMPORT.equals(book.sourceType)) return;
        try (Cursor c = db.rawQuery("SELECT COUNT(*) FROM local_volumes WHERE book_id=?", new String[]{book.id})) {
            if (c.moveToFirst() && c.getInt(0) > 0) {
                db.execSQL("UPDATE local_volumes SET status=? WHERE id=? AND status='staging'", new Object[]{book.status, book.id});
                return;
            }
        }
        db.execSQL("INSERT OR IGNORE INTO local_volumes "
                + "(id,book_id,fingerprint,title,format,relative_path,total_size,order_index,status,created_at,updated_at) "
                + "VALUES(?,?,?,?,?,?,?,0,?,?,?)", new Object[]{book.id, book.id, book.fingerprint,
                book.originalTitle, book.format, book.relativePath, book.totalSize, book.status, book.createdAt, book.updatedAt});
        db.execSQL("UPDATE local_volumes SET status=? WHERE id=?", new Object[]{book.status, book.id});
    }

    public LocalModels.Book findReadyByTitle(String title) {
        if (title == null || title.trim().isEmpty()) return null;
        String trimmed = title.trim();
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_BOOKS, null, "(original_title = ? OR user_title = ?) AND status = ?",
                new String[]{trimmed, trimmed, LocalModels.STATUS_READY}, null, null, "created_at DESC LIMIT 1")) {
            if (c != null && c.moveToFirst()) {
                return readBook(c);
            }
        }
        return null;
    }

    public DeletedFingerprint findDeletedByFingerprint(String fingerprint) {
        if (fingerprint == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_DELETED_FINGERPRINTS, null, "fingerprint = ?",
                new String[]{fingerprint}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return new DeletedFingerprint(
                        c.getString(c.getColumnIndexOrThrow("fingerprint")),
                        c.getString(c.getColumnIndexOrThrow("progress_key")),
                        c.getString(c.getColumnIndexOrThrow("user_title")),
                        c.getLong(c.getColumnIndexOrThrow("deleted_at"))
                );
            }
        }
        return null;
    }

    public DeletedFingerprint findDeletedByProgressKey(String progressKey) {
        if (progressKey == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_DELETED_FINGERPRINTS, null, "progress_key = ?",
                new String[]{progressKey}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return new DeletedFingerprint(
                        c.getString(c.getColumnIndexOrThrow("fingerprint")),
                        c.getString(c.getColumnIndexOrThrow("progress_key")),
                        c.getString(c.getColumnIndexOrThrow("user_title")),
                        c.getLong(c.getColumnIndexOrThrow("deleted_at"))
                );
            }
        }
        return null;
    }

    public List<LocalModels.Chapter> getChapters(String bookId) {
        if (bookId == null) return Collections.emptyList();
        SQLiteDatabase db = helper.getReadableDatabase();
        List<LocalModels.Chapter> result = new ArrayList<>();
        try (Cursor c = db.query(TABLE_CHAPTERS, null, "book_id = ?",
                new String[]{bookId}, null, null, "order_index ASC")) {
            while (c != null && c.moveToNext()) {
                result.add(readChapter(c));
            }
        }
        return result;
    }

    public LocalModels.Chapter getChapter(String chapterId) {
        if (chapterId == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_CHAPTERS, null, "id = ?",
                new String[]{chapterId}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return readChapter(c);
            }
        }
        return null;
    }

    public List<LocalModels.Page> getPages(String chapterId) {
        if (chapterId == null) return Collections.emptyList();
        SQLiteDatabase db = helper.getReadableDatabase();
        List<LocalModels.Page> result = new ArrayList<>();
        try (Cursor c = db.query(TABLE_PAGES, null, "chapter_id = ?",
                new String[]{chapterId}, null, null, "order_index ASC")) {
            while (c != null && c.moveToNext()) {
                result.add(readPage(c));
            }
        }
        return result;
    }

    public LocalModels.Page getPage(String pageId) {
        if (pageId == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_PAGES, null, "id = ?",
                new String[]{pageId}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return readPage(c);
            }
        }
        return null;
    }

    public LocalModels.Page getFirstPage(String bookId) {
        if (bookId == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.rawQuery("SELECT p.* FROM pages p JOIN chapters c ON c.id = p.chapter_id "
                + "WHERE p.book_id = ? ORDER BY c.order_index, p.order_index LIMIT 1", new String[]{bookId})) {
            if (c != null && c.moveToFirst()) {
                return readPage(c);
            }
        }
        return null;
    }

    public synchronized void commitImport(LocalModels.Book book, List<LocalModels.Chapter> chapters,
                                          Map<String, List<LocalModels.Page>> pagesByChapter) {
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransactionNonExclusive();
        try {
            // Remove any previous record from deleted_fingerprints
            if (LocalModels.STATUS_READY.equals(book.status)) {
                db.delete(TABLE_DELETED_FINGERPRINTS, "fingerprint = ?", new String[]{book.fingerprint});
            }

            // Insert book
            ContentValues bv = new ContentValues();
            bv.put("id", book.id);
            bv.put("fingerprint", book.fingerprint);
            bv.put("original_title", book.originalTitle);
            bv.put("user_title", book.userTitle);
            bv.put("format", book.format);
            bv.put("source_type", book.sourceType);
            bv.put("progress_key", book.progressKey);
            bv.put("relative_path", book.relativePath);
            bv.put("cover_path", book.coverPath);
            bv.put("total_size", book.totalSize);
            bv.put("chapter_count", book.chapterCount);
            bv.put("page_count", book.pageCount);
            bv.put("status", book.status);
            bv.put("created_at", book.createdAt);
            bv.put("updated_at", book.updatedAt);
            long rowId = db.insertWithOnConflict(TABLE_BOOKS, null, bv, SQLiteDatabase.CONFLICT_REPLACE);
            if (rowId == -1) {
                throw new android.database.SQLException("Failed to insert book: " + book.id);
            }

            // Insert chapters
            ensureDefaultVolume(db, book);
            if (LocalModels.SOURCE_TYPE_FILE_DOWNLOAD.equals(book.sourceType)) {
                db.delete(TABLE_PAGES, "book_id = ?", new String[]{book.id});
                db.delete(TABLE_CHAPTERS, "book_id = ?", new String[]{book.id});
            }
            if (chapters != null) {
                for (LocalModels.Chapter ch : chapters) {
                    ContentValues cv = new ContentValues();
                    cv.put("id", ch.id);
                    cv.put("book_id", ch.bookId);
                    cv.put("volume_id", ch.volumeId != null ? ch.volumeId
                            : LocalModels.SOURCE_TYPE_IMPORT.equals(book.sourceType) ? book.id : null);
                    cv.put("order_index", ch.orderIndex);
                    cv.put("title", ch.title);
                    cv.put("entry_path", ch.entryPath);
                    cv.put("page_count", ch.pageCount);
                    long chRow = db.insertWithOnConflict(TABLE_CHAPTERS, null, cv, SQLiteDatabase.CONFLICT_REPLACE);
                    if (chRow == -1) {
                        throw new android.database.SQLException("Failed to insert chapter: " + ch.id);
                    }

                    List<LocalModels.Page> pages = pagesByChapter != null ? pagesByChapter.get(ch.id) : null;
                    if (pages != null) {
                        for (LocalModels.Page pg : pages) {
                            ContentValues pv = new ContentValues();
                            pv.put("id", pg.id);
                            pv.put("book_id", pg.bookId);
                            pv.put("volume_id", pg.volumeId != null ? pg.volumeId : ch.volumeId != null ? ch.volumeId
                                    : LocalModels.SOURCE_TYPE_IMPORT.equals(book.sourceType) ? book.id : null);
                            pv.put("chapter_id", pg.chapterId);
                            pv.put("order_index", pg.orderIndex);
                            pv.put("entry_path", pg.entryPath);
                            pv.put("width", pg.width);
                            pv.put("height", pg.height);
                            pv.put("transformation", pg.transformation);
                            pv.put("mime_type", pg.mimeType);
                            long pgRow = db.insertWithOnConflict(TABLE_PAGES, null, pv, SQLiteDatabase.CONFLICT_REPLACE);
                            if (pgRow == -1) {
                                throw new android.database.SQLException("Failed to insert page: " + pg.id);
                            }
                        }
                    }
                }
            }

            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
    }

    public synchronized boolean renameBook(String bookId, String newTitle) {
        if (bookId == null) return false;
        SQLiteDatabase db = helper.getWritableDatabase();
        ContentValues cv = new ContentValues();
        cv.put("user_title", newTitle != null ? newTitle.trim() : null);
        cv.put("updated_at", System.currentTimeMillis());
        int rows = db.update(TABLE_BOOKS, cv, "id = ?", new String[]{bookId});
        return rows > 0;
    }

    public synchronized void appendVolume(LocalModels.Volume volume, ArchiveIndex.ParseResult index) {
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransactionNonExclusive();
        try {
            LocalModels.Book book = getBook(volume.seriesId);
            if (book == null || !LocalModels.STATUS_READY.equals(book.status))
                throw new IllegalStateException("漫画不存在或正在删除");
            if (getVolume(volume.id) != null) return;
            if (index.chapters.isEmpty()) throw new IllegalArgumentException("分卷没有章节");
            insertVolume(db, volume);
            db.execSQL("UPDATE local_volumes SET order_index=(SELECT COALESCE(MAX(order_index),-1)+1 "
                    + "FROM local_volumes WHERE book_id=? AND id!=?) WHERE id=?",
                    new Object[]{book.id, volume.id, volume.id});
            for (LocalModels.Chapter chapter : index.chapters) {
                if (!book.id.equals(chapter.bookId) || !volume.id.equals(chapter.volumeId))
                    throw new IllegalArgumentException("分卷章节归属错误");
            }
            // Existing chapters are retained. The Book row owns the series totals and display metadata.
            LocalModels.Book updated = new LocalModels.Book(book.id, book.fingerprint, book.originalTitle,
                    book.userTitle, book.format, book.sourceType, book.progressKey, book.relativePath,
                    book.coverPath, book.totalSize + volume.totalSize, book.chapterCount + index.chapters.size(),
                    book.pageCount + index.totalPages, book.status, book.createdAt, System.currentTimeMillis());
            commitImport(updated, index.chapters, index.pagesByChapter);
            reorderVolumeChapters(db, book.id);
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }

    private void reorderVolumeChapters(SQLiteDatabase db, String bookId) {
        List<LocalModels.Volume> volumes = getVolumes(bookId);
        int chapterOrder = 0;
        for (int i = 0; i < volumes.size(); i++) {
            LocalModels.Volume volume = volumes.get(i);
            db.execSQL("UPDATE local_volumes SET order_index=? WHERE id=?", new Object[]{i, volume.id});
            List<String> ids = new ArrayList<>();
            try (Cursor c = db.rawQuery("SELECT id FROM chapters WHERE book_id=? AND volume_id=? ORDER BY order_index,id",
                    new String[]{bookId, volume.id})) {
                while (c.moveToNext()) ids.add(c.getString(0));
            }
            for (String id : ids) db.execSQL("UPDATE chapters SET order_index=? WHERE id=?", new Object[]{chapterOrder++, id});
        }
    }

    public synchronized void moveVolume(String bookId, String volumeId, int direction) {
        List<LocalModels.Volume> volumes = getVolumes(bookId);
        int from = -1;
        for (int i = 0; i < volumes.size(); i++) if (volumes.get(i).id.equals(volumeId)) from = i;
        int to = from + Integer.signum(direction);
        if (from < 0 || to < 0 || to >= volumes.size()) return;
        Collections.swap(volumes, from, to);
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransactionNonExclusive();
        try {
            for (int i = 0; i < volumes.size(); i++)
                db.execSQL("UPDATE local_volumes SET order_index=? WHERE id=?", new Object[]{i, volumes.get(i).id});
            reorderVolumeChapters(db, bookId);
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }

    public boolean deleteVolume(String bookId, String volumeId, LocalStorageManager storage) {
        synchronized (storage) {
            synchronized (this) {
                LocalModels.Volume volume = getVolume(volumeId);
                if (volume == null) return true;
                if (!volume.seriesId.equals(bookId)) throw new IllegalArgumentException("分卷归属错误");
                if (getVolumes(bookId).size() == 1) return deleteBook(bookId, storage);
                SQLiteDatabase db = helper.getWritableDatabase();
                db.execSQL("UPDATE local_volumes SET status='deleting' WHERE id=?", new Object[]{volumeId});
                try {
                    File source = storage.getBookImportFile(volume.relativePath);
                    // Only app-owned copies can be removed; external originals are references.
                    boolean owned;
                    try { LocalStorageManager.assertPathInsideRoot(source, storage.getImportsDir()); owned = true; }
                    catch (java.io.IOException | SecurityException e) { owned = false; }
                    boolean shared = false;
                    for (LocalModels.Volume other : getVolumes(bookId))
                        if (!other.id.equals(volumeId) && other.relativePath.equals(volume.relativePath)) shared = true;
                    if (owned && !shared && !storage.deleteRecursively(source)) return false;
                    if (!storage.deleteRecursively(storage.getDerivedBookFile(volumeId, ".epub"))) return false;
                    if (!storage.clearDerivedPagesForBook(bookId)) return false;
                } catch (java.io.IOException | SecurityException e) { return false; }
                db.beginTransactionNonExclusive();
                try {
                    db.delete(TABLE_PAGES, "book_id=? AND volume_id=?", new String[]{bookId, volumeId});
                    db.delete(TABLE_CHAPTERS, "book_id=? AND volume_id=?", new String[]{bookId, volumeId});
                    db.delete(TABLE_VOLUMES, "id=?", new String[]{volumeId});
                    List<LocalModels.Volume> remaining = getVolumes(bookId);
                    LocalModels.Volume first = remaining.get(0);
                    db.execSQL("UPDATE books SET fingerprint=CASE WHEN fingerprint=? THEN 'series:'||id ELSE fingerprint END, "
                            + "chapter_count=(SELECT COUNT(*) FROM chapters WHERE book_id=?), "
                            + "page_count=(SELECT COUNT(*) FROM pages WHERE book_id=?),total_size=MAX(0,total_size-?),"
                            + "relative_path=?,format=?,cover_path=NULL,updated_at=? WHERE id=?", new Object[]{volume.fingerprint, bookId, bookId,
                            volume.totalSize, first.relativePath, first.format, System.currentTimeMillis(), bookId});
                    reorderVolumeChapters(db, bookId);
                    db.setTransactionSuccessful();
                    return true;
                } finally { db.endTransaction(); }
            }
        }
    }

    public synchronized void publishDownloadedChapter(LocalModels.Book incoming,LocalModels.Chapter chapter,
                                                       List<LocalModels.Page> pages) {
        LocalModels.Book previous=getBook(incoming.id);
        if(previous!=null && !LocalModels.STATUS_READY.equals(previous.status)) throw new IllegalStateException("漫画正在删除");
        int totalPages=pages.size(),chapterCount=1;
        for(LocalModels.Chapter existing:getChapters(incoming.id)) if(!existing.id.equals(chapter.id)) {
            totalPages+=existing.pageCount;chapterCount++;
        }
        LocalModels.Book merged=new LocalModels.Book(incoming.id,incoming.fingerprint,incoming.originalTitle,
                previous==null?incoming.userTitle:previous.userTitle,incoming.format,incoming.sourceType,
                incoming.progressKey,incoming.relativePath,incoming.coverPath,incoming.totalSize,chapterCount,totalPages,
                LocalModels.STATUS_READY,previous==null?incoming.createdAt:previous.createdAt,System.currentTimeMillis());
        SQLiteDatabase db=helper.getWritableDatabase();db.beginTransactionNonExclusive();
        try {
            db.delete(TABLE_PAGES,"chapter_id=?",new String[]{chapter.id});
            commitImport(merged,Collections.singletonList(chapter),Collections.singletonMap(chapter.id,pages));
            db.setTransactionSuccessful();
        } finally {db.endTransaction();}
    }

    public synchronized void removeDownloadedChapter(String bookId,String chapterId,long remainingBytes) {
        SQLiteDatabase db=helper.getWritableDatabase();db.beginTransactionNonExclusive();
        try {
            db.delete(TABLE_PAGES,"chapter_id=?",new String[]{chapterId});
            db.delete(TABLE_CHAPTERS,"id=? AND book_id=?",new String[]{chapterId,bookId});
            List<LocalModels.Chapter> remaining=getChapters(bookId);int pages=0;
            for(LocalModels.Chapter c:remaining)pages+=c.pageCount;
            ContentValues values=new ContentValues();values.put("chapter_count",remaining.size());values.put("page_count",pages);values.put("total_size",remainingBytes);
            db.update(TABLE_BOOKS,values,"id=?",new String[]{bookId});
            db.setTransactionSuccessful();
        } finally {db.endTransaction();}
    }

    public synchronized boolean updateBookCover(String bookId, String coverPath) {
        if (bookId == null) return false;
        SQLiteDatabase db = helper.getWritableDatabase();
        ContentValues cv = new ContentValues();
        cv.put("cover_path", coverPath);
        cv.put("updated_at", System.currentTimeMillis());
        int rows = db.update(TABLE_BOOKS, cv, "id = ?", new String[]{bookId});
        return rows > 0;
    }

    public synchronized boolean markDeleting(String bookId) {
        if (bookId == null) return false;
        SQLiteDatabase db = helper.getWritableDatabase();
        ContentValues cv = new ContentValues();
        cv.put("status", LocalModels.STATUS_DELETING);
        cv.put("updated_at", System.currentTimeMillis());
        int rows = db.update(TABLE_BOOKS, cv, "id = ?", new String[]{bookId});
        return rows > 0;
    }

    public synchronized boolean completeDeletion(String bookId) {
        if (bookId == null) return false;
        LocalModels.Book book = getBook(bookId);
        if (book == null) return false;

        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransactionNonExclusive();
        try {
            // Save tombstone in deleted_fingerprints
            ContentValues dfv = new ContentValues();
            dfv.put("fingerprint", book.fingerprint);
            dfv.put("progress_key", book.progressKey);
            dfv.put("user_title", book.userTitle);
            dfv.put("deleted_at", System.currentTimeMillis());
            if (db.insertWithOnConflict(TABLE_DELETED_FINGERPRINTS, null, dfv, SQLiteDatabase.CONFLICT_REPLACE) == -1) {
                throw new android.database.SQLException("Failed to preserve deleted book identity: " + bookId);
            }

            // Delete book and associated content
            db.delete(TABLE_PAGES, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_CHAPTERS, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_VOLUMES, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_BOOKS, "id = ?", new String[]{bookId});

            db.setTransactionSuccessful();
            return true;
        } finally {
            db.endTransaction();
        }
    }

    public synchronized void removeDeletedFingerprintByProgressKey(String progressKey) {
        if (progressKey == null) return;
        SQLiteDatabase db = helper.getWritableDatabase();
        db.delete(TABLE_DELETED_FINGERPRINTS, "progress_key = ?", new String[]{progressKey});
    }

    // Called on the local IO queue before accepting imports, never on the UI thread.
    public void recoverOrphanedStates(LocalStorageManager storageManager) {
        synchronized (storageManager) {
            for (LocalModels.Book book : listManagedBooks()) {
                repairLegacyVolumeSizes(book.id, storageManager);
                if (LocalModels.STATUS_READY.equals(book.status)) {
                    for (LocalModels.Volume volume : getVolumes(book.id))
                        if (LocalModels.STATUS_DELETING.equals(volume.status)) deleteVolume(book.id, volume.id, storageManager);
                }
                if (LocalModels.STATUS_READY.equals(book.status)) continue;
                if (storageManager.deleteBookFiles(book)) {
                    if (LocalModels.STATUS_DELETING.equals(book.status)) completeDeletion(book.id);
                    else discardPendingImport(book.id);
                }
            }
            java.util.Set<String> paths = new java.util.HashSet<>();
            java.util.Set<String> covers = new java.util.HashSet<>();
            java.util.Set<String> ids = new java.util.HashSet<>();
            // Failed cleanup records retain ownership of their remaining files for another retry.
            for (LocalModels.Book book : listManagedBooks()) {
                paths.add(book.relativePath);
                for (LocalModels.Volume volume : getVolumes(book.id)) paths.add(volume.relativePath);
                for (LocalModels.Chapter ch : getChapters(book.id)) {
                    if (ch.entryPath != null && !ch.entryPath.isEmpty()) {
                        paths.add(ch.entryPath);
                    }
                }
                covers.add(book.id + ".jpg");
                if(book.coverPath!=null)covers.add(book.coverPath);
                ids.add(book.id);
            }
            storageManager.cleanupOrphans(paths, covers);
            File[] pageDirs = storageManager.getPagesCacheDir().listFiles();
            if (pageDirs != null) for (File dir : pageDirs) {
                if (!ids.contains(dir.getName())) storageManager.deleteRecursively(dir);
            }
        }
    }

    private synchronized void repairLegacyVolumeSizes(String bookId, LocalStorageManager storage) {
        List<LocalModels.Volume> volumes = getVolumes(bookId);
        boolean legacy = false;
        for (LocalModels.Volume volume : volumes) if (volume.id.endsWith("_legacy")) legacy = true;
        if (!legacy) return;
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransactionNonExclusive();
        try {
            for (LocalModels.Volume volume : volumes) {
                try {
                    File file = storage.getBookImportFile(volume.relativePath);
                    if (file.isFile()) db.execSQL("UPDATE local_volumes SET total_size=? WHERE id=?", new Object[]{file.length(), volume.id});
                } catch (java.io.IOException | SecurityException ignored) { }
            }
            db.execSQL("UPDATE books SET total_size=(SELECT COALESCE(SUM(total_size),0) FROM local_volumes WHERE book_id=?) WHERE id=?",
                    new Object[]{bookId, bookId});
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }

    public boolean deleteBook(String bookId, LocalStorageManager storageManager) {
        // Invalidate new requests immediately; the file lock waits for an existing decode to finish.
        markDeleting(bookId);
        synchronized (storageManager) {
            LocalModels.Book book = getBook(bookId);
            if (book == null) return true;
            return storageManager.deleteBookFiles(book) && completeDeletion(bookId);
        }
    }

    private synchronized List<LocalModels.Book> listManagedBooks() {
        List<LocalModels.Book> books = new ArrayList<>();
        try (Cursor c = helper.getReadableDatabase().query(TABLE_BOOKS, null, null, null, null, null, null)) {
            while (c.moveToNext()) books.add(readBook(c));
        }
        return books;
    }

    public synchronized void discardPendingImport(String bookId) {
        LocalModels.Book book = getBook(bookId);
        if (book == null || !LocalModels.STATUS_STAGING.equals(book.status)) return;
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransactionNonExclusive();
        try {
            db.delete(TABLE_PAGES, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_CHAPTERS, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_VOLUMES, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_BOOKS, "id = ?", new String[]{bookId});
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }

    public java.util.Set<String> getAllActiveRelativePaths() {
        SQLiteDatabase db = helper.getReadableDatabase();
        java.util.Set<String> paths = new java.util.HashSet<>();
        try (Cursor c = db.query(TABLE_BOOKS, new String[]{"relative_path"}, "status = ?",
                new String[]{LocalModels.STATUS_READY}, null, null, null)) {
            while (c != null && c.moveToNext()) {
                String p = c.getString(0);
                if (p != null && !p.isEmpty()) paths.add(p);
            }
        }
        try (Cursor c = db.rawQuery("SELECT v.relative_path FROM local_volumes v JOIN books b ON b.id=v.book_id WHERE b.status='ready'", null)) {
            while (c.moveToNext()) if (c.getString(0) != null) paths.add(c.getString(0));
        }
        return paths;
    }

    public java.util.Set<String> getAllActiveCoverPaths() {
        SQLiteDatabase db = helper.getReadableDatabase();
        java.util.Set<String> paths = new java.util.HashSet<>();
        try (Cursor c = db.query(TABLE_BOOKS, new String[]{"cover_path"}, "status = ?",
                new String[]{LocalModels.STATUS_READY}, null, null, null)) {
            while (c != null && c.moveToNext()) {
                String p = c.getString(0);
                if (p != null && !p.isEmpty()) paths.add(p);
            }
        }
        return paths;
    }

    public LocalModels.Book findByProgressKey(String progressKey) {
        if (progressKey == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_BOOKS, null, "progress_key = ? AND status = ?",
                new String[]{progressKey, LocalModels.STATUS_READY}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return readBook(c);
            }
        }
        return null;
    }

    public int getNextUnnamedIndex() {
        SQLiteDatabase db = helper.getReadableDatabase();
        int maxIndex = 0;
        Pattern pattern = Pattern.compile("^未命名漫画\\s*(\\d+)$");
        try (Cursor c = db.query(TABLE_BOOKS, new String[]{"original_title", "user_title"}, null, null, null, null, null)) {
            while (c != null && c.moveToNext()) {
                String orig = c.getString(0);
                String user = c.getString(1);
                if (orig != null) {
                    Matcher m = pattern.matcher(orig.trim());
                    if (m.matches()) {
                        try {
                            maxIndex = Math.max(maxIndex, Integer.parseInt(m.group(1)));
                        } catch (NumberFormatException ignored) {}
                    }
                }
                if (user != null) {
                    Matcher m = pattern.matcher(user.trim());
                    if (m.matches()) {
                        try {
                            maxIndex = Math.max(maxIndex, Integer.parseInt(m.group(1)));
                        } catch (NumberFormatException ignored) {}
                    }
                }
            }
        }
        return maxIndex + 1;
    }

    private LocalModels.Book readBook(Cursor c) {
        return new LocalModels.Book(
                c.getString(c.getColumnIndexOrThrow("id")),
                c.getString(c.getColumnIndexOrThrow("fingerprint")),
                c.getString(c.getColumnIndexOrThrow("original_title")),
                c.getString(c.getColumnIndexOrThrow("user_title")),
                c.getString(c.getColumnIndexOrThrow("format")),
                c.getString(c.getColumnIndexOrThrow("source_type")),
                c.getString(c.getColumnIndexOrThrow("progress_key")),
                c.getString(c.getColumnIndexOrThrow("relative_path")),
                c.getString(c.getColumnIndexOrThrow("cover_path")),
                c.getLong(c.getColumnIndexOrThrow("total_size")),
                c.getInt(c.getColumnIndexOrThrow("chapter_count")),
                c.getInt(c.getColumnIndexOrThrow("page_count")),
                c.getString(c.getColumnIndexOrThrow("status")),
                c.getLong(c.getColumnIndexOrThrow("created_at")),
                c.getLong(c.getColumnIndexOrThrow("updated_at"))
        );
    }

    private LocalModels.Chapter readChapter(Cursor c) {
        return new LocalModels.Chapter(
                c.getString(c.getColumnIndexOrThrow("id")),
                c.getString(c.getColumnIndexOrThrow("book_id")),
                c.getString(c.getColumnIndexOrThrow("volume_id")),
                c.getInt(c.getColumnIndexOrThrow("order_index")),
                c.getString(c.getColumnIndexOrThrow("title")),
                c.getString(c.getColumnIndexOrThrow("entry_path")),
                c.getInt(c.getColumnIndexOrThrow("page_count"))
        );
    }

    private LocalModels.Page readPage(Cursor c) {
        return new LocalModels.Page(
                c.getString(c.getColumnIndexOrThrow("id")),
                c.getString(c.getColumnIndexOrThrow("book_id")),
                c.getString(c.getColumnIndexOrThrow("volume_id")),
                c.getString(c.getColumnIndexOrThrow("chapter_id")),
                c.getInt(c.getColumnIndexOrThrow("order_index")),
                c.getString(c.getColumnIndexOrThrow("entry_path")),
                c.getInt(c.getColumnIndexOrThrow("width")),
                c.getInt(c.getColumnIndexOrThrow("height")),
                c.getString(c.getColumnIndexOrThrow("transformation")),
                c.getString(c.getColumnIndexOrThrow("mime_type"))
        );
    }

    private static class OpenHelper extends SQLiteOpenHelper {
        OpenHelper(Context context) {
            super(context, DATABASE_NAME, null, DATABASE_VERSION);
            setWriteAheadLoggingEnabled(true);
        }

        @Override
        public void onCreate(SQLiteDatabase db) {
            db.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_BOOKS + " ("
                    + "id TEXT PRIMARY KEY, "
                    + "fingerprint TEXT UNIQUE NOT NULL, "
                    + "original_title TEXT NOT NULL, "
                    + "user_title TEXT, "
                    + "format TEXT NOT NULL, "
                    + "source_type TEXT NOT NULL, "
                    + "progress_key TEXT NOT NULL, "
                    + "relative_path TEXT NOT NULL, "
                    + "cover_path TEXT, "
                    + "total_size INTEGER NOT NULL, "
                    + "chapter_count INTEGER NOT NULL DEFAULT 0, "
                    + "page_count INTEGER NOT NULL DEFAULT 0, "
                    + "status TEXT NOT NULL DEFAULT 'ready', "
                    + "created_at INTEGER NOT NULL, "
                    + "updated_at INTEGER NOT NULL);");

            db.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_DELETED_FINGERPRINTS + " ("
                    + "fingerprint TEXT PRIMARY KEY, "
                    + "progress_key TEXT NOT NULL, "
                    + "user_title TEXT, "
                    + "deleted_at INTEGER NOT NULL);");

            db.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_CHAPTERS + " ("
                    + "id TEXT PRIMARY KEY, "
                    + "book_id TEXT NOT NULL, "
                    + "volume_id TEXT, "
                    + "order_index INTEGER NOT NULL, "
                    + "title TEXT NOT NULL, "
                    + "entry_path TEXT, "
                    + "page_count INTEGER NOT NULL DEFAULT 0);");

            db.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_PAGES + " ("
                    + "id TEXT PRIMARY KEY, "
                    + "book_id TEXT NOT NULL, "
                    + "volume_id TEXT, "
                    + "chapter_id TEXT NOT NULL, "
                    + "order_index INTEGER NOT NULL, "
                    + "entry_path TEXT NOT NULL, "
                    + "width INTEGER DEFAULT 0, "
                    + "height INTEGER DEFAULT 0, "
                    + "transformation TEXT, "
                    + "mime_type TEXT);");

            db.execSQL("CREATE INDEX IF NOT EXISTS idx_books_status ON " + TABLE_BOOKS + "(status);");
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_chapters_book ON " + TABLE_CHAPTERS + "(book_id, order_index);");
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_pages_chapter ON " + TABLE_PAGES + "(chapter_id, order_index);");
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_pages_book ON " + TABLE_PAGES + "(book_id);");
            createVolumes(db);
        }

        private static void createVolumes(SQLiteDatabase db) {
            db.execSQL("CREATE TABLE IF NOT EXISTS local_volumes (id TEXT PRIMARY KEY, book_id TEXT NOT NULL, "
                    + "fingerprint TEXT, title TEXT NOT NULL, format TEXT NOT NULL, relative_path TEXT NOT NULL, "
                    + "total_size INTEGER NOT NULL, order_index INTEGER NOT NULL, status TEXT NOT NULL, "
                    + "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(book_id,fingerprint))");
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_volumes_book ON local_volumes(book_id,order_index)");
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_volumes_fingerprint ON local_volumes(fingerprint)");
        }

        @Override
        public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
            if (oldVersion < 2) {
                db.execSQL("ALTER TABLE chapters ADD COLUMN volume_id TEXT");
                db.execSQL("ALTER TABLE pages ADD COLUMN volume_id TEXT");
                createVolumes(db);
                db.execSQL("INSERT INTO local_volumes SELECT id,id,fingerprint,original_title,format,relative_path,"
                        + "total_size,0,status,created_at,updated_at FROM books WHERE source_type='import'");
                db.execSQL("UPDATE chapters SET volume_id=book_id WHERE book_id IN (SELECT id FROM local_volumes)");
                // Old imports may already contain appended files. Keep each path separate without changing any locator.
                db.execSQL("INSERT INTO local_volumes SELECT c.id||'_legacy',c.book_id,NULL,c.title,"
                        + "b.format,c.entry_path,0,c.order_index,b.status,b.created_at,b.updated_at "
                        + "FROM chapters c JOIN books b ON b.id=c.book_id WHERE b.source_type='import' "
                        + "AND b.format!='folder' AND c.entry_path!=b.relative_path "
                        + "AND (lower(c.entry_path) LIKE '%.epub' OR lower(c.entry_path) LIKE '%.mobi' "
                        + "OR lower(c.entry_path) LIKE '%.azw%' OR lower(c.entry_path) LIKE '%.pdf' "
                        + "OR lower(c.entry_path) LIKE '%.zip' OR lower(c.entry_path) LIKE '%.cbz')");
                db.execSQL("UPDATE chapters SET volume_id=id||'_legacy' WHERE id||'_legacy' IN (SELECT id FROM local_volumes)");
                db.execSQL("UPDATE pages SET volume_id=(SELECT volume_id FROM chapters WHERE id=pages.chapter_id)");
                db.execSQL("UPDATE local_volumes SET order_index=COALESCE((SELECT MIN(order_index) FROM chapters WHERE volume_id=local_volumes.id),0)");
            }
        }
    }

    private static class NoBackupContext extends ContextWrapper {
        NoBackupContext(Context base) {
            super(base);
        }

        @Override
        public File getDatabasePath(String name) {
            File dir = getNoBackupFilesDir();
            if (dir == null) dir = getFilesDir();
            File dbDir = new File(dir, "database");
            if (!dbDir.exists()) dbDir.mkdirs();
            return new File(dbDir, name);
        }

        @Override
        public SQLiteDatabase openOrCreateDatabase(String name, int mode, SQLiteDatabase.CursorFactory factory) {
            return SQLiteDatabase.openOrCreateDatabase(getDatabasePath(name), factory);
        }

        @Override
        public SQLiteDatabase openOrCreateDatabase(String name, int mode, SQLiteDatabase.CursorFactory factory, DatabaseErrorHandler errorHandler) {
            return SQLiteDatabase.openOrCreateDatabase(getDatabasePath(name).getPath(), factory, errorHandler);
        }
    }

    private static class CustomDirectoryContext extends ContextWrapper {
        private final File dbFile;

        CustomDirectoryContext(Context base, File dbFile) {
            super(base);
            this.dbFile = dbFile;
        }

        @Override
        public File getDatabasePath(String name) {
            File parent = dbFile.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            return dbFile;
        }

        @Override
        public SQLiteDatabase openOrCreateDatabase(String name, int mode, SQLiteDatabase.CursorFactory factory) {
            return SQLiteDatabase.openOrCreateDatabase(getDatabasePath(name), factory);
        }

        @Override
        public SQLiteDatabase openOrCreateDatabase(String name, int mode, SQLiteDatabase.CursorFactory factory, DatabaseErrorHandler errorHandler) {
            return SQLiteDatabase.openOrCreateDatabase(getDatabasePath(name).getPath(), factory, errorHandler);
        }
    }
}
