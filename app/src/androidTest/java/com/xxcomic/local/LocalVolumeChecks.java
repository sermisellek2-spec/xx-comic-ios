package com.xxcomic.local;

import android.content.Context;
import android.database.sqlite.SQLiteDatabase;
import java.io.File;
import java.util.Collections;

/** Real SQLite checks, isolated from the user's library. */
public final class LocalVolumeChecks {
    public static int run(Context context) throws Exception {
        File root = new File(context.getCacheDir(), "volume_checks_" + System.nanoTime());
        LocalStorageManager storage = new LocalStorageManager(root);
        File file = new File(root, "checks.db");
        try (SQLiteDatabase db = SQLiteDatabase.openOrCreateDatabase(file, null)) {
            db.execSQL("CREATE TABLE books(id TEXT PRIMARY KEY,fingerprint TEXT UNIQUE NOT NULL,original_title TEXT NOT NULL,user_title TEXT,format TEXT NOT NULL,source_type TEXT NOT NULL,progress_key TEXT NOT NULL,relative_path TEXT NOT NULL,cover_path TEXT,total_size INTEGER NOT NULL,chapter_count INTEGER NOT NULL,page_count INTEGER NOT NULL,status TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)");
            db.execSQL("CREATE TABLE chapters(id TEXT PRIMARY KEY,book_id TEXT NOT NULL,order_index INTEGER NOT NULL,title TEXT NOT NULL,entry_path TEXT,page_count INTEGER NOT NULL)");
            db.execSQL("CREATE TABLE pages(id TEXT PRIMARY KEY,book_id TEXT NOT NULL,chapter_id TEXT NOT NULL,order_index INTEGER NOT NULL,entry_path TEXT NOT NULL,width INTEGER,height INTEGER,transformation TEXT,mime_type TEXT)");
            db.execSQL("CREATE TABLE deleted_fingerprints(fingerprint TEXT PRIMARY KEY,progress_key TEXT NOT NULL,user_title TEXT,deleted_at INTEGER NOT NULL)");
            db.execSQL("INSERT INTO books VALUES('book','fp1','漫画',NULL,'epub','import','book','book.epub',NULL,10,1,1,'ready',1,1)");
            db.execSQL("INSERT INTO chapters VALUES('old_ch','book',0,'卷1','book.epub',1)");
            db.execSQL("INSERT INTO pages VALUES('old_p','book','old_ch',0,'one.png',0,0,NULL,'image/png')");
            db.execSQL("INSERT INTO books VALUES('legacy','fpL','旧合集',NULL,'epub','import','legacy','legacy.epub',NULL,30,2,2,'ready',1,1)");
            db.execSQL("INSERT INTO chapters VALUES('legacy10','legacy',1,'卷10','legacy.epub',1)");
            db.execSQL("INSERT INTO chapters VALUES('legacy1','legacy',0,'卷1','legacy_1.epub',1)");
            db.execSQL("INSERT INTO pages VALUES('legacy_p10','legacy','legacy10',0,'10.png',0,0,NULL,'image/png')");
            db.execSQL("INSERT INTO pages VALUES('legacy_p1','legacy','legacy1',0,'1.png',0,0,NULL,'image/png')");
            db.setVersion(1);
        }
        LocalLibraryStore store = new LocalLibraryStore(context, file);
        try {
            require(store.getVolumes("book").size() == 1, "v1 gets one default volume");
            require("book".equals(store.getPage("old_p").volumeId), "old page locator retained");
            require("legacy1_legacy".equals(store.getVolumes("legacy").get(0).id), "v1 appended volumes keep their natural order");
            require("legacy1_legacy".equals(store.getPage("legacy_p1").volumeId), "old appended page owns its file");
            LocalModels.Volume volume = new LocalModels.Volume("book_vol_fp2", "book", "fp2", "卷2",
                    "mobi", "book_vol_fp2.mobi", 20, 1, "ready", 2, 2);
            LocalModels.Chapter chapter = new LocalModels.Chapter("book_vol_fp2_ch_0", "book", volume.id, 0, "卷2", volume.relativePath, 1);
            LocalModels.Page page = new LocalModels.Page("book_vol_fp2_ch_0_p_0", "book", volume.id, chapter.id, 0, "two.png", 0, 0, null, "image/png");
            ArchiveIndex.ParseResult index = new ArchiveIndex.ParseResult(Collections.singletonList(chapter),
                    Collections.singletonMap(chapter.id, Collections.singletonList(page)), 1, 0, "two.png", Collections.emptyList());
            store.appendVolume(volume, index);
            store.appendVolume(volume, index);
            require(store.getVolumes("book").size() == 2 && store.getBook("book").totalSize == 30, "repeat append is idempotent");
            require(store.getReadyVolumeCounts().get("book") == 2, "shelf volume count uses ready volumes");
            require("book".equals(store.findReadyByFingerprint("fp2").id), "appended fingerprint is indexed");
            require("mobi".equals(store.getVolume(store.getPage(page.id).volumeId).format), "mixed format survives persistence");
            store.moveVolume("book", volume.id, -1);
            require(chapter.id.equals(store.getChapters("book").get(0).id), "volume reorder retains chapter identity");
            require(store.deleteVolume("book", volume.id, storage), "delete one volume");
            require(store.getPage("old_p") != null && store.getPage(page.id) == null, "delete keeps other volume readable");
            require(store.getBook("book").pageCount == 1 && store.getBook("book").totalSize == 10, "delete updates series totals");
            store.appendVolume(volume, index);
            require(store.deleteVolume("book", "book", storage), "default volume can be removed independently");
            require(store.getPage(page.id) != null && store.getPage("old_p") == null, "removing default keeps other pages");
            require(store.findReadyByFingerprint("fp1") == null, "deleted first volume no longer deduplicates");
            require(store.getVolumes("book").size() == 1, "default volume is not recreated");
            return 15;
        } finally { store.close(); storage.deleteRecursively(root); }
    }
    private static void require(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
}
