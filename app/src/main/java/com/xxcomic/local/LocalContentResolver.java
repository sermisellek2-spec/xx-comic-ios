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

    private final LocalLibraryStore store;
    private final LocalStorageManager storageManager;

    public LocalContentResolver(LocalLibraryStore store, LocalStorageManager storageManager) {
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
        if (book == null) {
            throw new IOException("页面所属本地漫画未找到: " + page.bookId);
        }

        if (LocalModels.FORMAT_FOLDER.equals(book.format)) {
            File bookDir = storageManager.getBookImportFile(book.relativePath);
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
            InputStream entryStream = zip.getInputStream(entry);
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
        LocalModels.Page page = store.getPage(pageId);
        if (page == null) {
            throw new IOException("本地页面未找到: " + pageId);
        }
        LocalModels.Book book = store.getBook(page.bookId);
        if (book == null) {
            throw new IOException("页面所属本地漫画未找到: " + page.bookId);
        }

        if (LocalModels.FORMAT_FOLDER.equals(book.format)) {
            File bookDir = storageManager.getBookImportFile(book.relativePath);
            File pageFile = new File(bookDir, page.entryPath);
            LocalStorageManager.assertPathInsideRoot(pageFile, bookDir);
            if (pageFile.exists() && pageFile.length() > 0) {
                return pageFile;
            }
        }

        File derivedPagesDir = storageManager.getPagesCacheDir();
        File targetFile = new File(derivedPagesDir, pageId + ".tmp");
        if (targetFile.exists() && targetFile.length() > 0) {
            return targetFile;
        }

        File tempFile = new File(derivedPagesDir, pageId + "_" + System.currentTimeMillis() + ".writing");
        try (InputStream in = openPage(pageId);
             OutputStream out = new FileOutputStream(tempFile)) {
            byte[] buf = new byte[65536];
            int len;
            while ((len = in.read(buf)) > 0) {
                out.write(buf, 0, len);
            }
        }
        if (targetFile.exists()) targetFile.delete();
        if (!tempFile.renameTo(targetFile)) {
            if (targetFile.exists()) tempFile.delete();
            else return tempFile;
        }
        return targetFile;
    }

    public InputStream openCover(String bookId) throws IOException {
        LocalModels.Book book = store.getBook(bookId);
        if (book == null) return null;

        if (!TextUtils.isEmpty(book.coverPath)) {
            File coverFile = new File(book.coverPath);
            if (coverFile.exists() && coverFile.length() > 0) {
                return new FileInputStream(coverFile);
            }
        }

        LocalModels.Page firstPage = store.getFirstPage(bookId);
        if (firstPage != null) {
            return openPage(firstPage.id);
        }
        return null;
    }

    public Bitmap decodeCoverBitmap(String bookId, int targetWidth, int targetHeight) {
        try (InputStream in = openCover(bookId)) {
            if (in == null) return null;
            byte[] bytes = readAllBytes(in);
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
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
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
        } catch (Exception ignored) {
            return null;
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
}
