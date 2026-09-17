package com.xxcomic;

import android.content.Context;

import com.xxcomic.local.LocalModels;
import com.xxcomic.local.LocalLibraryStore;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class LocalLibraryChecks {
    private LocalLibraryChecks() {}

    public static int runChecks(Context context) throws Exception {
        int checks = 0;
        File testDb = new File(context.getCacheDir(), "test_local_library_" + System.currentTimeMillis() + ".db");
        if (testDb.exists()) testDb.delete();

        LocalLibraryStore store = new LocalLibraryStore(context, testDb);
        try {
            // 1. Initial empty check
            assertCondition(store.listBooks().isEmpty(), "Initial store should have 0 books");
            checks++;

            // 2. Commit a book
            String bookId = "book_test_1";
            String fingerprint = "sha256_dummy_hash_1";
            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, "测试漫画1", null,
                    LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, bookId,
                    "imports/test1.zip", null, 1024L * 1024L, 2, 5,
                    LocalModels.STATUS_READY, System.currentTimeMillis(), System.currentTimeMillis()
            );

            List<LocalModels.Chapter> chapters = new ArrayList<>();
            chapters.add(new LocalModels.Chapter("ch_1", bookId, 0, "第 1 话", "ch1", 2));
            chapters.add(new LocalModels.Chapter("ch_2", bookId, 1, "第 2 话", "ch2", 3));

            Map<String, List<LocalModels.Page>> pagesByChapter = new HashMap<>();
            List<LocalModels.Page> p1 = new ArrayList<>();
            p1.add(new LocalModels.Page("p_1_1", bookId, "ch_1", 0, "ch1/01.jpg", 800, 1200, null, "image/jpeg"));
            p1.add(new LocalModels.Page("p_1_2", bookId, "ch_1", 1, "ch1/02.jpg", 800, 1200, null, "image/jpeg"));
            pagesByChapter.put("ch_1", p1);

            List<LocalModels.Page> p2 = new ArrayList<>();
            p2.add(new LocalModels.Page("p_2_1", bookId, "ch_2", 0, "ch2/01.jpg", 800, 1200, null, "image/jpeg"));
            p2.add(new LocalModels.Page("p_2_2", bookId, "ch_2", 1, "ch2/02.jpg", 800, 1200, null, "image/jpeg"));
            p2.add(new LocalModels.Page("p_2_3", bookId, "ch_2", 2, "ch2/03.jpg", 800, 1200, null, "image/jpeg"));
            pagesByChapter.put("ch_2", p2);

            store.commitImport(book, chapters, pagesByChapter);

            // Verify book inserted
            LocalModels.Book queried = store.getBook(bookId);
            assertCondition(queried != null, "Book should be found by id");
            assertCondition("测试漫画1".equals(queried.getDisplayTitle()), "Original title matches");
            checks++;

            // Verify fingerprint lookup
            LocalModels.Book byFp = store.findReadyByFingerprint(fingerprint);
            assertCondition(byFp != null && bookId.equals(byFp.id), "Book found by fingerprint");
            checks++;

            // Verify chapters and pages
            List<LocalModels.Chapter> chList = store.getChapters(bookId);
            assertCondition(chList.size() == 2, "2 chapters retrieved");
            assertCondition("ch_1".equals(chList.get(0).id), "Chapter order correct");
            checks++;

            List<LocalModels.Page> pgList = store.getPages("ch_2");
            assertCondition(pgList.size() == 3, "3 pages in chapter 2");
            checks++;

            // 3. Rename book
            boolean renamed = store.renameBook(bookId, "自定义新名称");
            assertCondition(renamed, "Rename should succeed");
            LocalModels.Book renamedBook = store.getBook(bookId);
            assertCondition("自定义新名称".equals(renamedBook.getDisplayTitle()), "Renamed title reflected");
            assertCondition(bookId.equals(renamedBook.progressKey), "Progress key unchanged after rename");
            checks++;

            // 4. Delete book and verify tombstone in deleted_fingerprints
            store.completeDeletion(bookId);
            assertCondition(store.getBook(bookId) == null, "Book deleted from main table");
            assertCondition(store.getChapters(bookId).isEmpty(), "Chapters deleted");
            assertCondition(store.getPages("ch_1").isEmpty(), "Pages deleted");
            LocalLibraryStore.DeletedFingerprint df = store.findDeletedByFingerprint(fingerprint);
            assertCondition(df != null, "Fingerprint saved in deleted_fingerprints");
            assertCondition(bookId.equals(df.progressKey), "Progress key saved in deleted_fingerprints");
            assertCondition("自定义新名称".equals(df.userTitle), "User title saved in deleted_fingerprints");
            checks++;

            // 5. Re-import with same fingerprint: previous progress key and user title are restored
            String newBookId = "book_test_reimported";
            LocalModels.Book reimported = new LocalModels.Book(
                    newBookId, fingerprint, "测试漫画1", df.userTitle,
                    LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, df.progressKey,
                    "imports/test1_re.zip", null, 1024L * 1024L, 1, 1,
                    LocalModels.STATUS_READY, System.currentTimeMillis(), System.currentTimeMillis()
            );
            List<LocalModels.Chapter> reCh = Collections.singletonList(new LocalModels.Chapter("re_ch", newBookId, 0, "正文", "", 1));
            Map<String, List<LocalModels.Page>> rePg = Collections.singletonMap("re_ch",
                    Collections.singletonList(new LocalModels.Page("re_p", newBookId, "re_ch", 0, "01.jpg", 100, 100, null, "image/jpeg")));

            store.commitImport(reimported, reCh, rePg);

            assertCondition(store.findDeletedByFingerprint(fingerprint) == null, "Deleted fingerprint cleared after re-import");
            LocalModels.Book active = store.findReadyByFingerprint(fingerprint);
            assertCondition(active != null, "Reimported book active");
            assertCondition("自定义新名称".equals(active.getDisplayTitle()), "Custom title restored");
            assertCondition(bookId.equals(active.progressKey), "Original progress key restored");
            checks++;

            // 6. Test Unnamed Comic Index Generation
            int nextIndex = store.getNextUnnamedIndex();
            assertCondition(nextIndex == 1, "Initial unnamed index should be 1");
            checks++;

            LocalModels.Book unnamed1 = new LocalModels.Book(
                    "b_unnamed", "fp_unnamed", "未命名漫画 3", null,
                    LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog_un",
                    "imports/u.zip", null, 100L, 1, 1, LocalModels.STATUS_READY, 0L, 0L
            );
            store.commitImport(unnamed1, Collections.emptyList(), Collections.emptyMap());
            assertCondition(store.getNextUnnamedIndex() == 4, "Next unnamed index should be 4");
            checks++;

            // 7. Test orphan recovery
            LocalModels.Book stagingBook = new LocalModels.Book(
                    "b_staging", "fp_staging", "未完成导入", null,
                    LocalModels.FORMAT_ZIP, LocalModels.SOURCE_TYPE_IMPORT, "prog_st",
                    "staging/tmp.zip", null, 100L, 1, 1, LocalModels.STATUS_STAGING, 0L, 0L
            );
            store.commitImport(stagingBook, Collections.emptyList(), Collections.emptyMap());
            store.recoverOrphanedStates();
            assertCondition(store.getBook("b_staging") == null, "Staging book recovered and deleted");
            checks++;

        } finally {
            store.close();
            if (testDb.exists()) testDb.delete();
        }
        return checks;
    }

    private static void assertCondition(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError("LocalLibraryCheck failed: " + message);
        }
    }
}
