package com.xxcomic.local;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.text.TextUtils;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class LocalImporter {
    private final Context context;
    private final LocalStorageManager storageManager;
    private final LocalLibraryStore store;

    public LocalImporter(Context context, LocalStorageManager storageManager, LocalLibraryStore store) {
        this.context = context.getApplicationContext();
        this.storageManager = storageManager;
        this.store = store;
    }

    public LocalModels.Book importArchiveUri(Uri uri, String rawDisplayName,
                                             LocalModels.ImportProgressCallback callback) throws Exception {
        ContentResolver resolver = context.getContentResolver();
        String displayName = rawDisplayName;
        if (TextUtils.isEmpty(displayName)) {
            displayName = queryDisplayName(resolver, uri);
        }
        if (TextUtils.isEmpty(displayName)) {
            displayName = "comic.zip";
        }

        File stagingFile = storageManager.createStagingFile("import_zip_", ".tmp");
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");

        long bytesCopied = 0L;
        byte[] buffer = new byte[65536];

        try {
            try (InputStream in = resolver.openInputStream(uri);
                 OutputStream out = new FileOutputStream(stagingFile)) {
                if (in == null) throw new IOException("无法打开所选文件数据流: " + uri);

                int len;
                while ((len = in.read(buffer)) > 0) {
                    if (callback != null && callback.isCancelled()) {
                        throw new InterruptedException("用户取消导入");
                    }
                    sha256.update(buffer, 0, len);
                    out.write(buffer, 0, len);
                    bytesCopied += len;

                    if (!storageManager.hasSufficientSpace(bytesCopied)) {
                        throw new IOException("设备可用存储空间不足（需至少保留 256MiB 空间）");
                    }
                    if (callback != null) {
                        callback.onProgress(bytesCopied, -1L, "正在复制文件: " + formatBytes(bytesCopied));
                    }
                }
            }

            String fingerprint = toHexString(sha256.digest());

            // Check if active book with same fingerprint already exists
            LocalModels.Book existing = store.findReadyByFingerprint(fingerprint);
            if (existing != null) {
                storageManager.deleteRecursively(stagingFile);
                return existing;
            }

            // Check if there is a deleted tombstone to restore progressKey & userTitle
            LocalLibraryStore.DeletedFingerprint tombstone = store.findDeletedByFingerprint(fingerprint);
            String bookId = "local_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
            String progressKey = tombstone != null ? tombstone.progressKey : bookId;
            String userTitle = tombstone != null ? tombstone.userTitle : null;

            // Determine title
            String originalTitle = stripExtension(displayName);
            if (TextUtils.isEmpty(originalTitle) || originalTitle.trim().isEmpty()) {
                originalTitle = "未命名漫画 " + store.getNextUnnamedIndex();
            } else {
                originalTitle = originalTitle.trim();
            }

            if (callback != null) {
                callback.onProgress(bytesCopied, bytesCopied, "正在解析章节与页面...");
            }

            ArchiveIndex.ParseResult parseResult = ArchiveIndex.indexArchive(stagingFile, bookId);

            // Extract cover
            String coverPath = null;
            File coverTarget = storageManager.getCoverFile(bookId);
            if (extractArchiveCover(stagingFile, parseResult.firstValidPageEntry, coverTarget)) {
                coverPath = coverTarget.getAbsolutePath();
            }

            // Move staging file to imports
            String format = displayName.toLowerCase(Locale.US).endsWith(".cbz") ? LocalModels.FORMAT_CBZ : LocalModels.FORMAT_ZIP;
            String targetFileName = bookId + (LocalModels.FORMAT_CBZ.equals(format) ? ".cbz" : ".zip");
            File targetImportFile = storageManager.getBookImportFile(targetFileName);
            storageManager.promoteStagingToImports(stagingFile, targetImportFile);

            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, originalTitle, userTitle, format,
                    LocalModels.SOURCE_TYPE_IMPORT, progressKey, targetFileName,
                    coverPath, targetImportFile.length(), parseResult.chapters.size(),
                    parseResult.totalPages, LocalModels.STATUS_READY,
                    System.currentTimeMillis(), System.currentTimeMillis()
            );

            store.commitImport(book, parseResult.chapters, parseResult.pagesByChapter);
            return book;
        } catch (Exception error) {
            storageManager.deleteRecursively(stagingFile);
            throw error;
        }
    }

    public LocalModels.Book importFolderUri(Uri treeUri, String rawFolderName,
                                            LocalModels.ImportProgressCallback callback) throws Exception {
        ContentResolver resolver = context.getContentResolver();
        String rootDocId = DocumentsContract.getTreeDocumentId(treeUri);

        String folderName = rawFolderName;
        if (TextUtils.isEmpty(folderName)) {
            Uri rootDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocId);
            folderName = queryDisplayName(resolver, rootDocUri);
        }
        if (TextUtils.isEmpty(folderName)) {
            folderName = "comic_folder";
        }

        String stagingName = "import_folder_" + System.currentTimeMillis();
        File stagingDir = storageManager.createStagingDirectory(stagingName);

        try {
            long[] bytesCopied = new long[]{0L};
            copyDocumentTreeNative(treeUri, rootDocId, stagingDir, bytesCopied, callback);

            // Index copied folder
            FolderIndexResult folderResult = indexFolder(stagingDir);
            if (folderResult.validImages.isEmpty()) {
                throw new IOException("文件夹内没有找到可支持的漫画图片");
            }

            String fingerprint = computeFolderManifestFingerprint(stagingDir, folderResult.validImages);

            // Check if active book with same fingerprint already exists
            LocalModels.Book existing = store.findReadyByFingerprint(fingerprint);
            if (existing != null) {
                storageManager.deleteRecursively(stagingDir);
                return existing;
            }

            // Check tombstone
            LocalLibraryStore.DeletedFingerprint tombstone = store.findDeletedByFingerprint(fingerprint);
            String bookId = "local_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
            String progressKey = tombstone != null ? tombstone.progressKey : bookId;
            String userTitle = tombstone != null ? tombstone.userTitle : null;

            String originalTitle = folderName.trim();
            if (TextUtils.isEmpty(originalTitle)) {
                originalTitle = "未命名漫画 " + store.getNextUnnamedIndex();
            }

            if (callback != null) {
                callback.onProgress(bytesCopied[0], bytesCopied[0], "正在整理章节结构...");
            }

            FolderChaptersResult chaptersResult = buildFolderChapters(stagingDir, folderResult.validImages, bookId);

            // Extract cover
            String coverPath = null;
            File coverTarget = storageManager.getCoverFile(bookId);
            if (extractFileCover(new File(stagingDir, chaptersResult.firstPageEntry), coverTarget)) {
                coverPath = coverTarget.getAbsolutePath();
            }

            // Move staging folder to imports
            File targetImportDir = storageManager.getBookImportFile(bookId);
            storageManager.promoteStagingToImports(stagingDir, targetImportDir);

            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, originalTitle, userTitle, LocalModels.FORMAT_FOLDER,
                    LocalModels.SOURCE_TYPE_IMPORT, progressKey, bookId,
                    coverPath, bytesCopied[0], chaptersResult.chapters.size(),
                    chaptersResult.totalPages, LocalModels.STATUS_READY,
                    System.currentTimeMillis(), System.currentTimeMillis()
            );

            store.commitImport(book, chaptersResult.chapters, chaptersResult.pagesByChapter);
            return book;
        } catch (Exception error) {
            storageManager.deleteRecursively(stagingDir);
            throw error;
        }
    }

    private void copyDocumentTreeNative(Uri treeUri, String parentDocId, File targetDir, long[] bytesCopied,
                                        LocalModels.ImportProgressCallback callback) throws Exception {
        ContentResolver resolver = context.getContentResolver();
        Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId);

        String[] projection = new String[]{
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
        };

        byte[] buf = new byte[65536];

        try (Cursor cursor = resolver.query(childrenUri, projection, null, null, null)) {
            if (cursor == null) return;
            while (cursor.moveToNext()) {
                if (callback != null && callback.isCancelled()) {
                    throw new InterruptedException("用户取消导入");
                }
                String docId = cursor.getString(0);
                String name = cursor.getString(1);
                String mimeType = cursor.getString(2);

                if (name == null || ArchiveIndex.isIgnoredMetadata(name)) continue;

                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mimeType)) {
                    File subDir = new File(targetDir, name);
                    if (!subDir.exists() && !subDir.mkdirs()) {
                        throw new IOException("无法创建目录: " + subDir.getAbsolutePath());
                    }
                    copyDocumentTreeNative(treeUri, docId, subDir, bytesCopied, callback);
                } else if (ArchiveIndex.hasImageExtension(name)) {
                    File targetFile = new File(targetDir, name);
                    Uri fileDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId);
                    try (InputStream in = resolver.openInputStream(fileDocUri);
                         OutputStream out = new FileOutputStream(targetFile)) {
                        if (in == null) continue;
                        int len;
                        while ((len = in.read(buf)) > 0) {
                            out.write(buf, 0, len);
                            bytesCopied[0] += len;
                            if (!storageManager.hasSufficientSpace(bytesCopied[0])) {
                                throw new IOException("设备可用存储空间不足（需至少保留 256MiB 空间）");
                            }
                        }
                    }
                    if (callback != null) {
                        callback.onProgress(bytesCopied[0], -1L, "正在复制图片: " + formatBytes(bytesCopied[0]));
                    }
                }
            }
        }
    }

    public static class ValidFolderImage {
        public final String relativePath;
        public final String strippedPath;
        public final String mimeType;

        public ValidFolderImage(String relativePath, String strippedPath, String mimeType) {
            this.relativePath = relativePath;
            this.strippedPath = strippedPath;
            this.mimeType = mimeType;
        }
    }

    public static class FolderIndexResult {
        public final List<String> validImages;

        public FolderIndexResult(List<String> validImages) {
            this.validImages = validImages;
        }
    }

    public static FolderIndexResult indexFolder(File rootDir) {
        List<String> found = new ArrayList<>();
        collectImagesRecursive(rootDir, "", found);
        return new FolderIndexResult(found);
    }

    private static void collectImagesRecursive(File current, String prefix, List<String> result) {
        File[] children = current.listFiles();
        if (children == null) return;
        for (File child : children) {
            String name = child.getName();
            if (ArchiveIndex.isIgnoredMetadata(name)) continue;
            String rel = prefix.isEmpty() ? name : prefix + "/" + name;
            if (child.isDirectory()) {
                collectImagesRecursive(child, rel, result);
            } else if (ArchiveIndex.hasImageExtension(name)) {
                // Verify magic
                byte[] header = new byte[16];
                int readBytes = 0;
                try (InputStream in = new FileInputStream(child)) {
                    readBytes = in.read(header);
                } catch (Exception ignored) {}
                if (readBytes >= 4 && ArchiveIndex.isImageMagic(header, readBytes)) {
                    result.add(rel.replace('\\', '/'));
                }
            }
        }
    }

    public static String computeFolderManifestFingerprint(File rootDir, List<String> imageRelPaths) throws Exception {
        List<String> sorted = new ArrayList<>(imageRelPaths);
        Collections.sort(sorted, new NaturalPathOrder());

        MessageDigest manifestDigest = MessageDigest.getInstance("SHA-256");
        byte[] buf = new byte[65536];

        for (String rel : sorted) {
            File img = new File(rootDir, rel);
            MessageDigest fileDigest = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new FileInputStream(img)) {
                int len;
                while ((len = in.read(buf)) > 0) {
                    fileDigest.update(buf, 0, len);
                }
            }
            String fileHash = toHexString(fileDigest.digest());
            manifestDigest.update((rel + ":" + fileHash + "\n").getBytes(StandardCharsets.UTF_8));
        }

        return toHexString(manifestDigest.digest());
    }

    public static class FolderChaptersResult {
        public final List<LocalModels.Chapter> chapters;
        public final Map<String, List<LocalModels.Page>> pagesByChapter;
        public final int totalPages;
        public final String firstPageEntry;

        public FolderChaptersResult(List<LocalModels.Chapter> chapters,
                                    Map<String, List<LocalModels.Page>> pagesByChapter,
                                    int totalPages, String firstPageEntry) {
            this.chapters = chapters;
            this.pagesByChapter = pagesByChapter;
            this.totalPages = totalPages;
            this.firstPageEntry = firstPageEntry;
        }
    }

    public static FolderChaptersResult buildFolderChapters(File rootDir, List<String> rawPaths, String bookId) {
        String wrapperPrefix = findCommonFolderWrapper(rawPaths);

        List<ValidFolderImage> list = new ArrayList<>();
        for (String p : rawPaths) {
            String stripped = p;
            if (!wrapperPrefix.isEmpty() && p.startsWith(wrapperPrefix)) {
                stripped = p.substring(wrapperPrefix.length());
            }
            String mime = ArchiveIndex.detectMimeType(null, 0, p);
            list.add(new ValidFolderImage(p, stripped, mime));
        }

        Collections.sort(list, (a, b) -> new NaturalPathOrder().compare(a.strippedPath, b.strippedPath));

        List<ValidFolderImage> rootImages = new ArrayList<>();
        Map<String, List<ValidFolderImage>> subFolders = new LinkedHashMap<>();

        for (ValidFolderImage img : list) {
            int slash = img.strippedPath.indexOf('/');
            if (slash < 0) {
                rootImages.add(img);
            } else {
                String firstSeg = img.strippedPath.substring(0, slash);
                List<ValidFolderImage> group = subFolders.get(firstSeg);
                if (group == null) {
                    group = new ArrayList<>();
                    subFolders.put(firstSeg, group);
                }
                group.add(img);
            }
        }

        List<LocalModels.Chapter> chapters = new ArrayList<>();
        Map<String, List<LocalModels.Page>> pagesByChapter = new HashMap<>();
        int chapterOrder = 0;

        if (subFolders.isEmpty()) {
            String chapterId = bookId + "_ch_0";
            LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, 0, "正文", "", rootImages.size());
            chapters.add(ch);

            List<LocalModels.Page> pageList = new ArrayList<>();
            for (int i = 0; i < rootImages.size(); i++) {
                ValidFolderImage v = rootImages.get(i);
                String pageId = chapterId + "_p_" + i;
                pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.relativePath, 0, 0, null, v.mimeType));
            }
            pagesByChapter.put(chapterId, pageList);
        } else {
            if (!rootImages.isEmpty()) {
                String chapterId = bookId + "_ch_" + (chapterOrder++);
                LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, chapters.size(), "未分章", "", rootImages.size());
                chapters.add(ch);

                List<LocalModels.Page> pageList = new ArrayList<>();
                for (int i = 0; i < rootImages.size(); i++) {
                    ValidFolderImage v = rootImages.get(i);
                    String pageId = chapterId + "_p_" + i;
                    pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.relativePath, 0, 0, null, v.mimeType));
                }
                pagesByChapter.put(chapterId, pageList);
            }

            List<String> folderNames = new ArrayList<>(subFolders.keySet());
            Collections.sort(folderNames, new NaturalPathOrder());

            for (String folderName : folderNames) {
                List<ValidFolderImage> entriesInFolder = subFolders.get(folderName);
                String chapterId = bookId + "_ch_" + (chapterOrder++);
                LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, chapters.size(), folderName, folderName, entriesInFolder.size());
                chapters.add(ch);

                List<LocalModels.Page> pageList = new ArrayList<>();
                for (int i = 0; i < entriesInFolder.size(); i++) {
                    ValidFolderImage v = entriesInFolder.get(i);
                    String pageId = chapterId + "_p_" + i;
                    pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.relativePath, 0, 0, null, v.mimeType));
                }
                pagesByChapter.put(chapterId, pageList);
            }
        }

        return new FolderChaptersResult(chapters, pagesByChapter, list.size(), list.get(0).relativePath);
    }

    private static String findCommonFolderWrapper(List<String> paths) {
        String currentPrefix = "";
        while (true) {
            String candidateFolder = null;
            boolean allMatch = true;
            for (String p : paths) {
                String remainder = p.substring(currentPrefix.length());
                int slash = remainder.indexOf('/');
                if (slash < 0) {
                    allMatch = false;
                    break;
                }
                String folder = remainder.substring(0, slash);
                if (candidateFolder == null) {
                    candidateFolder = folder;
                } else if (!candidateFolder.equals(folder)) {
                    allMatch = false;
                    break;
                }
            }
            if (allMatch && candidateFolder != null && !candidateFolder.isEmpty()) {
                currentPrefix += candidateFolder + "/";
            } else {
                break;
            }
        }
        return currentPrefix;
    }

    private boolean extractArchiveCover(File zipFile, String entryName, File targetCoverFile) {
        try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(zipFile)) {
            ZipEntry entry = zip.getEntry(entryName);
            if (entry == null) return false;
            try (InputStream in = zip.getInputStream(entry)) {
                return decodeAndSaveCover(in, targetCoverFile);
            }
        } catch (Exception e) {
            return false;
        }
    }

    private boolean extractFileCover(File imageFile, File targetCoverFile) {
        if (!imageFile.exists()) return false;
        try (InputStream in = new FileInputStream(imageFile)) {
            return decodeAndSaveCover(in, targetCoverFile);
        } catch (Exception e) {
            return false;
        }
    }

    private boolean decodeAndSaveCover(InputStream in, File targetCoverFile) {
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            byte[] bytes = readAllBytes(in);
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false;

            BitmapFactory.Options opts = new BitmapFactory.Options();
            int maxDim = Math.max(bounds.outWidth, bounds.outHeight);
            opts.inSampleSize = 1;
            while (maxDim / (opts.inSampleSize * 2) >= 600) {
                opts.inSampleSize *= 2;
            }
            Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
            if (bitmap == null) return false;

            File parent = targetCoverFile.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();

            try (OutputStream out = new FileOutputStream(targetCoverFile)) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out);
            }
            bitmap.recycle();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static byte[] readAllBytes(InputStream in) throws IOException {
        byte[] buf = new byte[8192];
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        int len;
        while ((len = in.read(buf)) > 0) {
            out.write(buf, 0, len);
        }
        return out.toByteArray();
    }

    private String queryDisplayName(ContentResolver resolver, Uri uri) {
        try (Cursor cursor = resolver.query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                return cursor.getString(0);
            }
        } catch (Exception ignored) {}
        return null;
    }

    private static String stripExtension(String name) {
        if (name == null) return "";
        int dot = name.lastIndexOf('.');
        if (dot > 0) return name.substring(0, dot);
        return name;
    }

    private static String toHexString(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format(Locale.US, "%02x", b & 0xff));
        }
        return sb.toString();
    }

    private static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        char unit = "KMGTPE".charAt(exp - 1);
        return String.format(Locale.US, "%.1f %cB", bytes / Math.pow(1024, exp), unit);
    }
}
