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

public class LocalLibraryStore {
    private static final String DATABASE_NAME = "local_library.db";
    private static final int DATABASE_VERSION = 1;

    private static final String TABLE_BOOKS = "books";
    private static final String TABLE_DELETED_FINGERPRINTS = "deleted_fingerprints";
    private static final String TABLE_CHAPTERS = "chapters";
    private static final String TABLE_PAGES = "pages";

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
        recoverOrphanedStates();
    }

    // For testing or custom database file location
    public LocalLibraryStore(Context context, File customDbFile) {
        this.helper = new OpenHelper(new CustomDirectoryContext(context, customDbFile));
        recoverOrphanedStates();
    }

    public synchronized void close() {
        helper.close();
    }

    public synchronized List<LocalModels.Book> listBooks() {
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

    public synchronized int getBookCount() {
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.rawQuery("SELECT COUNT(*) FROM " + TABLE_BOOKS + " WHERE status = ?",
                new String[]{LocalModels.STATUS_READY})) {
            if (c != null && c.moveToFirst()) {
                return c.getInt(0);
            }
        } catch (Exception ignored) {}
        return 0;
    }

    public synchronized LocalModels.Book getBook(String bookId) {
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

    public synchronized LocalModels.Book findReadyByFingerprint(String fingerprint) {
        if (fingerprint == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_BOOKS, null, "fingerprint = ? AND status = ?",
                new String[]{fingerprint, LocalModels.STATUS_READY}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                return readBook(c);
            }
        }
        return null;
    }

    public synchronized DeletedFingerprint findDeletedByFingerprint(String fingerprint) {
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

    public synchronized List<LocalModels.Chapter> getChapters(String bookId) {
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

    public synchronized LocalModels.Chapter getChapter(String chapterId) {
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

    public synchronized List<LocalModels.Page> getPages(String chapterId) {
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

    public synchronized LocalModels.Page getPage(String pageId) {
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

    public synchronized LocalModels.Page getFirstPage(String bookId) {
        if (bookId == null) return null;
        SQLiteDatabase db = helper.getReadableDatabase();
        try (Cursor c = db.query(TABLE_PAGES, null, "book_id = ?",
                new String[]{bookId}, null, null, "order_index ASC LIMIT 1")) {
            if (c != null && c.moveToFirst()) {
                return readPage(c);
            }
        }
        return null;
    }

    public synchronized void commitImport(LocalModels.Book book, List<LocalModels.Chapter> chapters,
                                          Map<String, List<LocalModels.Page>> pagesByChapter) {
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransaction();
        try {
            // Remove any previous record from deleted_fingerprints
            db.delete(TABLE_DELETED_FINGERPRINTS, "fingerprint = ?", new String[]{book.fingerprint});

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
            db.insertWithOnConflict(TABLE_BOOKS, null, bv, SQLiteDatabase.CONFLICT_REPLACE);

            // Insert chapters
            if (chapters != null) {
                for (LocalModels.Chapter ch : chapters) {
                    ContentValues cv = new ContentValues();
                    cv.put("id", ch.id);
                    cv.put("book_id", ch.bookId);
                    cv.put("order_index", ch.orderIndex);
                    cv.put("title", ch.title);
                    cv.put("entry_path", ch.entryPath);
                    cv.put("page_count", ch.pageCount);
                    db.insertWithOnConflict(TABLE_CHAPTERS, null, cv, SQLiteDatabase.CONFLICT_REPLACE);

                    List<LocalModels.Page> pages = pagesByChapter != null ? pagesByChapter.get(ch.id) : null;
                    if (pages != null) {
                        for (LocalModels.Page pg : pages) {
                            ContentValues pv = new ContentValues();
                            pv.put("id", pg.id);
                            pv.put("book_id", pg.bookId);
                            pv.put("chapter_id", pg.chapterId);
                            pv.put("order_index", pg.orderIndex);
                            pv.put("entry_path", pg.entryPath);
                            pv.put("width", pg.width);
                            pv.put("height", pg.height);
                            pv.put("transformation", pg.transformation);
                            pv.put("mime_type", pg.mimeType);
                            db.insertWithOnConflict(TABLE_PAGES, null, pv, SQLiteDatabase.CONFLICT_REPLACE);
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
        db.beginTransaction();
        try {
            // Save tombstone in deleted_fingerprints
            ContentValues dfv = new ContentValues();
            dfv.put("fingerprint", book.fingerprint);
            dfv.put("progress_key", book.progressKey);
            dfv.put("user_title", book.userTitle);
            dfv.put("deleted_at", System.currentTimeMillis());
            db.insertWithOnConflict(TABLE_DELETED_FINGERPRINTS, null, dfv, SQLiteDatabase.CONFLICT_REPLACE);

            // Delete book and associated content
            db.delete(TABLE_PAGES, "book_id = ?", new String[]{bookId});
            db.delete(TABLE_CHAPTERS, "book_id = ?", new String[]{bookId});
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

    public synchronized void recoverOrphanedStates() {
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransaction();
        try {
            // Clean up books left in staging or deleting
            List<String> toDelete = new ArrayList<>();
            try (Cursor c = db.query(TABLE_BOOKS, new String[]{"id", "status"},
                    "status = ? OR status = ?",
                    new String[]{LocalModels.STATUS_STAGING, LocalModels.STATUS_DELETING},
                    null, null, null)) {
                while (c != null && c.moveToNext()) {
                    toDelete.add(c.getString(0));
                }
            }
            for (String bookId : toDelete) {
                db.delete(TABLE_PAGES, "book_id = ?", new String[]{bookId});
                db.delete(TABLE_CHAPTERS, "book_id = ?", new String[]{bookId});
                db.delete(TABLE_BOOKS, "id = ?", new String[]{bookId});
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
    }

    public synchronized int getNextUnnamedIndex() {
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
                    + "order_index INTEGER NOT NULL, "
                    + "title TEXT NOT NULL, "
                    + "entry_path TEXT, "
                    + "page_count INTEGER NOT NULL DEFAULT 0);");

            db.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_PAGES + " ("
                    + "id TEXT PRIMARY KEY, "
                    + "book_id TEXT NOT NULL, "
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
        }

        @Override
        public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
            // v1 initial schema
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
