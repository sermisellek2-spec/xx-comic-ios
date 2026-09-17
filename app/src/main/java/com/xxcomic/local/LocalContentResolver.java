package com.xxcomic.local;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.text.TextUtils;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class LocalContentResolver {
    public static final String SCHEME = "local://";
    public static final String PREFIX_PAGE = "local://page/";
    public static final String PREFIX_COVER = "local://cover/";
    public static final String PREFIX_CHAPTER = "local://chapter/";

    public interface ContentIndex {
        LocalModels.Book getBook(String id);
        LocalModels.Page getPage(String id);
        LocalModels.Page getFirstPage(String bookId);
    }

    private final ContentIndex store;
    private final LocalStorageManager storageManager;

    public LocalContentResolver(ContentIndex store, LocalStorageManager storageManager) {
        this.store = store;
        this.storageManager = storageManager;
    }

    public static boolean isLocalUrl(String url) {
        return url != null && url.startsWith(SCHEME);
    }

    public static boolean isLocalPageUrl(String url) {
        return url != null && url.startsWith(PREFIX_PAGE);
    }

    public static boolean isLocalCoverUrl(String url) {
        return url != null && url.startsWith(PREFIX_COVER);
    }

    public static boolean isLocalChapterUrl(String url) {
        return url != null && url.startsWith(PREFIX_CHAPTER);
    }

    public static String buildPageUrl(String pageId) {
        return PREFIX_PAGE + pageId;
    }

    public static String buildCoverUrl(String bookId) {
        return PREFIX_COVER + bookId;
    }

    public static String buildChapterUrl(String chapterId) {
        return PREFIX_CHAPTER + chapterId;
    }

    public static String extractId(String localUrl, String prefix) {
        if (localUrl == null || !localUrl.startsWith(prefix)) return "";
        return localUrl.substring(prefix.length());
    }

    public InputStream openPage(String pageId) throws IOException {
        LocalModels.Page page = store.getPage(pageId);
        if (page == null) {
            throw new IOException("本地页面未找到: " + pageId);
        }
        LocalModels.Book book = store.getBook(page.bookId);
        if (book == null || !LocalModels.STATUS_READY.equals(book.status)) {
            throw new IOException("页面所属本地漫画未找到或正在删除中: " + page.bookId);
        }

        if (LocalModels.FORMAT_FOLDER.equals(book.format)) {
            File bookDir = storageManager.getBookContentFile(book);
            File pageFile = new File(bookDir, page.entryPath);
            LocalStorageManager.assertPathInsideRoot(pageFile, bookDir);
            if (!pageFile.exists()) {
                throw new IOException("本地图片文件不存在: " + pageFile.getAbsolutePath());
            }
            return new FileInputStream(pageFile);
        } else {
            File zipFile = storageManager.getBookImportFile(book.relativePath);
            if (!zipFile.exists()) {
                throw new IOException("本地漫画压缩包不存在: " + zipFile.getAbsolutePath());
            }
            ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(zipFile);
            ZipEntry entry = zip.getEntry(page.entryPath);
            if (entry == null) {
                try { zip.close(); } catch (IOException ignored) {}
                throw new IOException("压缩包内页面条目未找到: " + page.entryPath);
            }
            InputStream entryStream;
            try { entryStream = zip.getInputStream(entry); }
            catch (IOException | RuntimeException error) {
                try { zip.close(); } catch (IOException ignored) { }
                throw error;
            }
            return new FilterInputStream(entryStream) {
                @Override
                public void close() throws IOException {
                    try {
                        super.close();
                    } finally {
                        zip.close();
                    }
                }
            };
        }
    }

    public File materializePage(String pageId) throws IOException {
        synchronized (storageManager) {
            return materializePageLocked(pageId);
        }
    }

    public interface PageFileReader<T> {
        T read(File file) throws IOException;
    }

    // Keep the file alive until the reader finishes decoding, including during cache cleanup/deletion.
    public <T> T withPageFile(String pageId, PageFileReader<T> reader) throws IOException {
        synchronized (storageManager) {
            return reader.read(materializePageLocked(pageId));
        }
    }

    private File materializePageLocked(String pageId) throws IOException {
        LocalImporter.checkCancelled(null);
        LocalModels.Page page = store.getPage(pageId);
        if (page == null) {
            throw new IOException("本地页面未找到: " + pageId);
        }
        LocalModels.Book book = store.getBook(page.bookId);
        if (book == null || !LocalModels.STATUS_READY.equals(book.status)) {
            throw new IOException("页面所属本地漫画未找到或正在删除中: " + page.bookId);
        }

        if (LocalModels.FORMAT_FOLDER.equals(book.format)) {
            File bookDir = storageManager.getBookContentFile(book);
            File pageFile = new File(bookDir, page.entryPath);
            LocalStorageManager.assertPathInsideRoot(pageFile, bookDir);
            if (pageFile.exists() && pageFile.length() > 0) {
                return pageFile;
            }
            throw new IOException("本地图片文件不存在: " + page.entryPath);
        }

        File bookCacheDir = new File(storageManager.getPagesCacheDir(), book.id);
        LocalStorageManager.assertPathInsideRoot(bookCacheDir, storageManager.getPagesCacheDir());
        if (!bookCacheDir.exists() && !bookCacheDir.mkdirs()) throw new IOException("无法创建本地图片缓存");
        File targetFile = new File(bookCacheDir, pageId + ".tmp");
        LocalStorageManager.assertPathInsideRoot(targetFile, bookCacheDir);
        if (targetFile.exists() && targetFile.length() > 0) {
            targetFile.setLastModified(System.currentTimeMillis());
            return targetFile;
        }
        storageManager.enforcePagesCacheLimit(200L * 1024L * 1024L - ArchiveIndex.MAX_PAGE_BYTES);
        storageManager.checkUsableSpace(0);
        File tempFile = File.createTempFile("page_", ".writing", bookCacheDir);
        boolean success = false;
        try {
            try (InputStream in = openPage(pageId);
                 OutputStream out = new FileOutputStream(tempFile)) {
                byte[] buf = new byte[65536];
                int len;
                long totalWritten = 0L;
                while ((len = in.read(buf)) > 0) {
                    if (Thread.currentThread().isInterrupted()) {
                        throw new IOException("页面解压已被中断: " + pageId);
                    }
                    totalWritten += len;
                    if (totalWritten > ArchiveIndex.MAX_PAGE_BYTES) {
                        throw new IOException("单页解压大小超出安全限制（最大 128MiB）: " + pageId);
                    }
                    storageManager.checkUsableSpace(len);
                    out.write(buf, 0, len);
                }
            }
            LocalImporter.checkCancelled(null);
            LocalModels.Book latest = store.getBook(page.bookId);
            if (latest == null || !LocalModels.STATUS_READY.equals(latest.status)) {
                throw new IOException("本地漫画正在删除中");
            }
            if (!tempFile.renameTo(targetFile)) {
                throw new IOException("无法发布解压页面到缓存目录: " + targetFile.getAbsolutePath());
            }
            success = true;
            return targetFile;
        } finally {
            if (!success) tempFile.delete();
        }
    }

    public Bitmap decodeCoverBitmap(String bookId, int targetWidth, int targetHeight) {
        synchronized (storageManager) {
            LocalModels.Book book = store.getBook(bookId);
            if (book == null || !LocalModels.STATUS_READY.equals(book.status)) return null;
            if (!TextUtils.isEmpty(book.coverPath)) {
                File coverFile = new File(book.coverPath);
                if (coverFile.exists() && coverFile.length() > 0) {
                    try {
                        BitmapFactory.Options bounds = new BitmapFactory.Options();
                        bounds.inJustDecodeBounds = true;
                        BitmapFactory.decodeFile(coverFile.getAbsolutePath(), bounds);
                        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;

                        BitmapFactory.Options opts = new BitmapFactory.Options();
                        opts.inSampleSize = 1;
                        if (targetWidth > 0 && targetHeight > 0) {
                            int sample = 1;
                            while (bounds.outWidth / (sample * 2) >= targetWidth && bounds.outHeight / (sample * 2) >= targetHeight) {
                                sample *= 2;
                            }
                            opts.inSampleSize = sample;
                        }
                        while ((long)(bounds.outWidth / opts.inSampleSize) * (bounds.outHeight / opts.inSampleSize) > 4_000_000L) opts.inSampleSize *= 2;
                        return BitmapFactory.decodeFile(coverFile.getAbsolutePath(), opts);
                    } catch (Exception ignored) {
                        return null;
                    }
                }
            }

            LocalModels.Page first = store.getFirstPage(bookId);
            if (first == null) return null;
            try {
                return withPageFile(first.id, file -> {
                    BitmapFactory.Options options = new BitmapFactory.Options();
                    options.inJustDecodeBounds = true;
                    BitmapFactory.decodeFile(file.getAbsolutePath(), options);
                    if (options.outWidth <= 0 || options.outHeight <= 0) return null;
                    options.inJustDecodeBounds = false;
                    options.inSampleSize = 1;
                    while (Math.max(options.outWidth, options.outHeight) / options.inSampleSize > 600) options.inSampleSize *= 2;
                    Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
                    return first.transformation != null && first.transformation.startsWith("jm:")
                            ? com.xxcomic.JmImageTransform.restore(bitmap, first.transformation.substring(3)) : bitmap;
                });
            } catch (Exception ignored) {
                return null;
            }
        }
    }
}
