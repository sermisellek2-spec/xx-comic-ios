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
    public static final int MAX_FOLDER_DEPTH = 5;
    public static final int MAX_FOLDER_FILES = 5000;
    public static final long MAX_SINGLE_FILE_BYTES = 100L * 1024L * 1024L; // 100 MiB
    public static final long MAX_TOTAL_BYTES = 20L * 1024L * 1024L * 1024L; // 20 GiB

    private final Context context;
    private final LocalStorageManager storageManager;
    private final LocalLibraryStore store;

    public static class BoundedInputStream extends InputStream {
        private final InputStream in;
        private final long maxBytes;
        private long readBytes = 0;

        public BoundedInputStream(InputStream in, long maxBytes) {
            this.in = in;
            this.maxBytes = maxBytes;
        }

        @Override
        public int read() throws IOException {
            if (readBytes >= maxBytes) {
                throw new IOException("读取大小超过上限: " + maxBytes);
            }
            int b = in.read();
            if (b != -1) readBytes++;
            return b;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            if (readBytes >= maxBytes) {
                throw new IOException("读取大小超过上限: " + maxBytes);
            }
            int toRead = (int) Math.min((long) len, maxBytes - readBytes);
            int n = in.read(b, off, toRead);
            if (n > 0) readBytes += n;
            return n;
        }

        @Override
        public void close() throws IOException {
            in.close();
        }
    }

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

        File stagingFile = storageManager.createStagingFile("import_zip_", ".tmp");
        File targetImportFile = null;
        File coverTarget = null;
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

                    if (!storageManager.hasUsableMargin()) {
                        throw new IOException("设备可用存储空间不足（需至少保留 256MiB 空间）");
                    }
                    if (callback != null) {
                        callback.onProgress(bytesCopied, -1L, "正在复制文件: " + formatBytes(bytesCopied));
                    }
                }
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            String fingerprint = toHexString(sha256.digest());

            // Check if active book with same fingerprint already exists
            LocalModels.Book existing = store.findReadyByFingerprint(fingerprint);
            if (existing != null) {
                storageManager.deleteRecursively(stagingFile);
                return existing;
            }

            // Restore stable progressKey & userTitle from tombstone, or create stable id
            LocalLibraryStore.DeletedFingerprint tombstone = store.findDeletedByFingerprint(fingerprint);
            String progressKey = (tombstone != null && tombstone.progressKey != null)
                    ? tombstone.progressKey
                    : LocalModels.buildStableBookId(fingerprint);
            String bookId = progressKey;
            String userTitle = tombstone != null ? tombstone.userTitle : null;

            // Determine title
            String originalTitle = stripExtension(displayName);
            if (TextUtils.isEmpty(originalTitle) || originalTitle.trim().isEmpty()) {
                originalTitle = "未命名漫画 " + store.getNextUnnamedIndex();
            } else {
                originalTitle = originalTitle.trim();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            if (callback != null) {
                callback.onProgress(bytesCopied, bytesCopied, "正在解析章节与页面...");
            }

            ArchiveIndex.ParseResult parseResult = ArchiveIndex.indexArchive(stagingFile, bookId);

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Extract cover with candidate fallback
            String coverPath = null;
            coverTarget = storageManager.getCoverFile(bookId);
            if (extractArchiveCover(stagingFile, parseResult.candidateCoverEntries, coverTarget)) {
                coverPath = coverTarget.getAbsolutePath();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Move staging file to imports
            String format = (displayName != null && displayName.toLowerCase(Locale.US).endsWith(".cbz"))
                    ? LocalModels.FORMAT_CBZ : LocalModels.FORMAT_ZIP;
            String targetFileName = bookId + (LocalModels.FORMAT_CBZ.equals(format) ? ".cbz" : ".zip");
            targetImportFile = storageManager.getBookImportFile(targetFileName);
            storageManager.promoteStagingToImports(stagingFile, targetImportFile);

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, originalTitle, userTitle, format,
                    LocalModels.SOURCE_TYPE_IMPORT, progressKey, targetFileName,
                    coverPath, targetImportFile.length(), parseResult.chapters.size(),
                    parseResult.totalPages, LocalModels.STATUS_READY,
                    System.currentTimeMillis(), System.currentTimeMillis()
            );

            store.commitImport(book, parseResult.chapters, parseResult.pagesByChapter);
            return book;
        } catch (Throwable error) {
            storageManager.deleteRecursively(stagingFile);
            if (targetImportFile != null && targetImportFile.exists()) {
                storageManager.deleteRecursively(targetImportFile);
            }
            if (coverTarget != null && coverTarget.exists()) {
                coverTarget.delete();
            }
            if (error instanceof Exception) throw (Exception) error;
            throw new IOException(error.getMessage(), error);
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

        String stagingName = "import_folder_" + System.currentTimeMillis();
        File stagingDir = storageManager.createStagingDirectory(stagingName);
        File targetImportDir = null;
        File coverTarget = null;

        try {
            long[] bytesCopied = new long[]{0L};
            int[] fileCount = new int[]{0};
            copyDocumentTreeNative(treeUri, rootDocId, stagingDir, 0, fileCount, bytesCopied, callback);

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Index copied folder
            FolderIndexResult folderResult = indexFolder(stagingDir);
            if (folderResult.validImages.isEmpty()) {
                throw new IOException("文件夹内没有找到可支持的漫画图片");
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            String fingerprint = computeFolderManifestFingerprint(stagingDir, folderResult.validImages);

            // Check if active book with same fingerprint already exists
            LocalModels.Book existing = store.findReadyByFingerprint(fingerprint);
            if (existing != null) {
                storageManager.deleteRecursively(stagingDir);
                return existing;
            }

            // Restore stable progressKey & userTitle from tombstone, or create stable id
            LocalLibraryStore.DeletedFingerprint tombstone = store.findDeletedByFingerprint(fingerprint);
            String progressKey = (tombstone != null && tombstone.progressKey != null)
                    ? tombstone.progressKey
                    : LocalModels.buildStableBookId(fingerprint);
            String bookId = progressKey;
            String userTitle = tombstone != null ? tombstone.userTitle : null;

            String originalTitle = folderName != null ? folderName.trim() : "";
            if (TextUtils.isEmpty(originalTitle)) {
                originalTitle = "未命名漫画 " + store.getNextUnnamedIndex();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            if (callback != null) {
                callback.onProgress(bytesCopied[0], bytesCopied[0], "正在整理章节结构...");
            }

            FolderChaptersResult chaptersResult = buildFolderChapters(stagingDir, folderResult.validImages, bookId);

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Extract cover with candidate fallback
            String coverPath = null;
            coverTarget = storageManager.getCoverFile(bookId);
            if (extractFileCover(stagingDir, chaptersResult.candidateCoverEntries, coverTarget)) {
                coverPath = coverTarget.getAbsolutePath();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Move staging folder to imports
            targetImportDir = storageManager.getBookImportFile(bookId);
            storageManager.promoteStagingToImports(stagingDir, targetImportDir);

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, originalTitle, userTitle, LocalModels.FORMAT_FOLDER,
                    LocalModels.SOURCE_TYPE_IMPORT, progressKey, bookId,
                    coverPath, bytesCopied[0], chaptersResult.chapters.size(),
                    chaptersResult.totalPages, LocalModels.STATUS_READY,
                    System.currentTimeMillis(), System.currentTimeMillis()
            );

            store.commitImport(book, chaptersResult.chapters, chaptersResult.pagesByChapter);
            return book;
        } catch (Throwable error) {
            storageManager.deleteRecursively(stagingDir);
            if (targetImportDir != null && targetImportDir.exists()) {
                storageManager.deleteRecursively(targetImportDir);
            }
            if (coverTarget != null && coverTarget.exists()) {
                coverTarget.delete();
            }
            if (error instanceof Exception) throw (Exception) error;
            throw new IOException(error.getMessage(), error);
        }
    }

    public static String sanitizeSegmentName(String rawName) {
        if (rawName == null) return "unnamed";
        String name = rawName.replace('\\', '/').trim();
        int lastSlash = name.lastIndexOf('/');
        if (lastSlash >= 0) {
            name = name.substring(lastSlash + 1).trim();
        }
        if (name.isEmpty() || name.equals(".") || name.equals("..")) {
            return "unnamed";
        }
        return name;
    }

    private void copyDocumentTreeNative(Uri treeUri, String parentDocId, File targetDir,
                                        int depth, int[] fileCount, long[] bytesCopied,
                                        LocalModels.ImportProgressCallback callback) throws Exception {
        if (depth > MAX_FOLDER_DEPTH) return;
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
                String cleanName = sanitizeSegmentName(name);

                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mimeType)) {
                    File subDir = new File(targetDir, cleanName);
                    LocalStorageManager.assertPathInsideRoot(subDir, targetDir);
                    if (!subDir.exists() && !subDir.mkdirs()) {
                        throw new IOException("无法创建目录: " + subDir.getAbsolutePath());
                    }
                    copyDocumentTreeNative(treeUri, docId, subDir, depth + 1, fileCount, bytesCopied, callback);
                } else if (ArchiveIndex.hasImageExtension(cleanName)) {
                    fileCount[0]++;
                    if (fileCount[0] > MAX_FOLDER_FILES) {
                        throw new IOException("文件夹包含图片数量超过安全上限（最多 " + MAX_FOLDER_FILES + " 张）");
                    }

                    File targetFile = new File(targetDir, cleanName);
                    LocalStorageManager.assertPathInsideRoot(targetFile, targetDir);

                    Uri fileDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId);
                    try (InputStream in = resolver.openInputStream(fileDocUri);
                         OutputStream out = new FileOutputStream(targetFile)) {
                        if (in == null) continue;
                        long fileWritten = 0L;
                        int len;
                        while ((len = in.read(buf)) > 0) {
                            if (callback != null && callback.isCancelled()) {
                                throw new InterruptedException("用户取消导入");
                            }
                            fileWritten += len;
                            if (fileWritten > MAX_SINGLE_FILE_BYTES) {
                                throw new IOException("单张图片文件大小超出限制（最大 100MiB）: " + cleanName);
                            }
                            out.write(buf, 0, len);
                            bytesCopied[0] += len;
                            if (bytesCopied[0] > MAX_TOTAL_BYTES) {
                                throw new IOException("文件夹解压总大小超出上限（最大 20GiB）");
                            }
                            if (!storageManager.hasUsableMargin()) {
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

    public static FolderIndexResult indexFolder(File rootDir) throws IOException {
        List<String> found = new ArrayList<>();
        collectImagesRecursive(rootDir, "", found, 0);
        if (found.isEmpty()) {
            throw new IOException("未找到有效的漫画图片: " + rootDir.getAbsolutePath());
        }
        return new FolderIndexResult(found);
    }

    private static void collectImagesRecursive(File current, String prefix, List<String> result, int depth) throws IOException {
        if (depth > MAX_FOLDER_DEPTH) {
            throw new IOException("目录层级过深（最多支持 5 层）: " + current.getAbsolutePath());
        }
        File[] children = current.listFiles();
        if (children == null) return;
        for (File child : children) {
            String name = child.getName();
            if (ArchiveIndex.isIgnoredMetadata(name)) continue;
            String rel = prefix.isEmpty() ? name : prefix + "/" + name;
            if (child.isDirectory()) {
                collectImagesRecursive(child, rel, result, depth + 1);
            } else if (ArchiveIndex.hasImageExtension(name)) {
                byte[] header = new byte[4096];
                int readBytes = 0;
                try (InputStream in = new FileInputStream(child)) {
                    int n;
                    while (readBytes < header.length && (n = in.read(header, readBytes, header.length - readBytes)) != -1) {
                        readBytes += n;
                    }
                } catch (Exception ignored) {}
                if (ArchiveIndex.validateImageBytes(header, readBytes, child.length(), name)) {
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
        public final List<String> candidateCoverEntries;

        public FolderChaptersResult(List<LocalModels.Chapter> chapters,
                                    Map<String, List<LocalModels.Page>> pagesByChapter,
                                    int totalPages, String firstPageEntry,
                                    List<String> candidateCoverEntries) {
            this.chapters = chapters;
            this.pagesByChapter = pagesByChapter;
            this.totalPages = totalPages;
            this.firstPageEntry = firstPageEntry;
            this.candidateCoverEntries = candidateCoverEntries != null ? candidateCoverEntries : Collections.emptyList();
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
            String chapterId = LocalModels.buildStableChapterId(bookId, 0);
            LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, 0, "正文", "", rootImages.size());
            chapters.add(ch);

            List<LocalModels.Page> pageList = new ArrayList<>();
            for (int i = 0; i < rootImages.size(); i++) {
                ValidFolderImage v = rootImages.get(i);
                String pageId = LocalModels.buildStablePageId(chapterId, i);
                pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.relativePath, 0, 0, null, v.mimeType));
            }
            pagesByChapter.put(chapterId, pageList);
        } else {
            if (!rootImages.isEmpty()) {
                String chapterId = LocalModels.buildStableChapterId(bookId, chapterOrder++);
                LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, chapters.size(), "未分章", "", rootImages.size());
                chapters.add(ch);

                List<LocalModels.Page> pageList = new ArrayList<>();
                for (int i = 0; i < rootImages.size(); i++) {
                    ValidFolderImage v = rootImages.get(i);
                    String pageId = LocalModels.buildStablePageId(chapterId, i);
                    pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.relativePath, 0, 0, null, v.mimeType));
                }
                pagesByChapter.put(chapterId, pageList);
            }

            List<String> folderNames = new ArrayList<>(subFolders.keySet());
            Collections.sort(folderNames, new NaturalPathOrder());

            for (String folderName : folderNames) {
                List<ValidFolderImage> entriesInFolder = subFolders.get(folderName);
                String chapterId = LocalModels.buildStableChapterId(bookId, chapterOrder++);
                LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, chapters.size(), folderName, folderName, entriesInFolder.size());
                chapters.add(ch);

                List<LocalModels.Page> pageList = new ArrayList<>();
                for (int i = 0; i < entriesInFolder.size(); i++) {
                    ValidFolderImage v = entriesInFolder.get(i);
                    String pageId = LocalModels.buildStablePageId(chapterId, i);
                    pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.relativePath, 0, 0, null, v.mimeType));
                }
                pagesByChapter.put(chapterId, pageList);
            }
        }

        List<String> candidateCovers = new ArrayList<>();
        for (ValidFolderImage v : list) {
            candidateCovers.add(v.relativePath);
        }
        return new FolderChaptersResult(chapters, pagesByChapter, list.size(), list.get(0).relativePath, candidateCovers);
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

    private boolean extractArchiveCover(File zipFile, List<String> candidateEntries, File targetCoverFile) {
        if (candidateEntries == null || candidateEntries.isEmpty()) return false;
        try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(zipFile)) {
            for (String entryName : candidateEntries) {
                ZipEntry entry = zip.getEntry(entryName);
                if (entry == null) continue;

                BitmapFactory.Options bounds = new BitmapFactory.Options();
                bounds.inJustDecodeBounds = true;
                try (InputStream in = zip.getInputStream(entry)) {
                    BitmapFactory.decodeStream(in, null, bounds);
                } catch (Exception e) {
                    continue;
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) continue;

                int maxDim = Math.max(bounds.outWidth, bounds.outHeight);
                BitmapFactory.Options opts = new BitmapFactory.Options();
                opts.inSampleSize = 1;
                while (maxDim / (opts.inSampleSize * 2) >= 600) {
                    opts.inSampleSize *= 2;
                }

                Bitmap bitmap = null;
                try (InputStream in = new BoundedInputStream(zip.getInputStream(entry), ArchiveIndex.MAX_PAGE_BYTES)) {
                    bitmap = BitmapFactory.decodeStream(in, null, opts);
                } catch (Exception e) {
                    continue;
                }
                if (bitmap == null) continue;

                File parent = targetCoverFile.getParentFile();
                if (parent != null && !parent.exists()) parent.mkdirs();

                try (OutputStream out = new FileOutputStream(targetCoverFile)) {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out);
                    return true;
                } catch (Exception e) {
                    if (targetCoverFile.exists()) targetCoverFile.delete();
                } finally {
                    bitmap.recycle();
                }
            }
        } catch (Exception ignored) {}
        return false;
    }

    private boolean extractFileCover(File rootDir, List<String> candidatePaths, File targetCoverFile) {
        if (candidatePaths == null || candidatePaths.isEmpty()) return false;
        for (String relPath : candidatePaths) {
            File file = new File(rootDir, relPath);
            if (!file.exists() || file.length() < 32) continue;

            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            try (InputStream in = new FileInputStream(file)) {
                BitmapFactory.decodeStream(in, null, bounds);
            } catch (Exception e) {
                continue;
            }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) continue;

            int maxDim = Math.max(bounds.outWidth, bounds.outHeight);
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inSampleSize = 1;
            while (maxDim / (opts.inSampleSize * 2) >= 600) {
                opts.inSampleSize *= 2;
            }

            Bitmap bitmap = null;
            try (InputStream in = new BoundedInputStream(new FileInputStream(file), ArchiveIndex.MAX_PAGE_BYTES)) {
                bitmap = BitmapFactory.decodeStream(in, null, opts);
            } catch (Exception e) {
                continue;
            }
            if (bitmap == null) continue;

            File parent = targetCoverFile.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();

            try (OutputStream out = new FileOutputStream(targetCoverFile)) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out);
                return true;
            } catch (Exception e) {
                if (targetCoverFile.exists()) targetCoverFile.delete();
            } finally {
                bitmap.recycle();
            }
        }
        return false;
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
