package com.xxcomic.local;

import android.content.Context;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class LocalStorageManager {
    public static final long MIN_RESERVED_FREE_BYTES = 256L * 1024L * 1024L; // 256 MiB

    private final File libraryRoot;
    private final File importsDir;
    private final File downloadsDir;
    private final File stagingDir;
    private final File derivedDir;
    private final File coversDir;
    private final File pagesCacheDir;

    public LocalStorageManager(Context context) {
        this(resolveLibraryRoot(context));
    }

    public LocalStorageManager(File libraryRoot) {
        this.libraryRoot = libraryRoot;
        this.importsDir = new File(libraryRoot, "imports");
        this.downloadsDir = new File(libraryRoot, "downloads");
        this.stagingDir = new File(libraryRoot, "staging");
        this.derivedDir = new File(libraryRoot, "derived");
        this.coversDir = new File(derivedDir, "covers");
        this.pagesCacheDir = new File(derivedDir, "pages");
        ensureDirectories();
    }

    private static File resolveLibraryRoot(Context context) {
        File noBackup = context.getNoBackupFilesDir();
        if (noBackup == null) {
            noBackup = context.getFilesDir();
        }
        return new File(noBackup, "library");
    }

    public synchronized void ensureDirectories() {
        if (!libraryRoot.exists()) libraryRoot.mkdirs();
        if (!importsDir.exists()) importsDir.mkdirs();
        if (!downloadsDir.exists()) downloadsDir.mkdirs();
        if (!stagingDir.exists()) stagingDir.mkdirs();
        if (!derivedDir.exists()) derivedDir.mkdirs();
        if (!coversDir.exists()) coversDir.mkdirs();
        if (!pagesCacheDir.exists()) pagesCacheDir.mkdirs();
    }

    public File getLibraryRoot() {
        return libraryRoot;
    }

    public File getImportsDir() {
        return importsDir;
    }

    public File getDownloadsDir() { return downloadsDir; }

    public File getDownloadFile(String relativePath) throws IOException {
        if(relativePath==null || relativePath.trim().isEmpty()) throw new IOException("下载路径为空");
        File file=new File(downloadsDir,relativePath);
        assertPathInsideRoot(file,downloadsDir);
        if(file.getCanonicalFile().equals(downloadsDir.getCanonicalFile())) throw new IOException("不能把全部下载作为单本漫画路径");
        return file;
    }

    public File getBookContentFile(LocalModels.Book book) throws IOException {
        if (book == null) throw new IOException("漫画对象为空");
        if (book.relativePath != null && (book.relativePath.startsWith("/") || book.relativePath.startsWith("\\")
                || book.relativePath.startsWith("file://") || new File(book.relativePath).isAbsolute())) {
            String path = book.relativePath.startsWith("file://") ? book.relativePath.substring(7) : book.relativePath;
            return new File(path);
        }
        return LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType)
                ? getDownloadFile(book.relativePath) : getBookImportFile(book.relativePath);
    }

    public File getStagingDir() {
        return stagingDir;
    }

    public File getDerivedDir() {
        return derivedDir;
    }

    public synchronized File getDerivedBookFile(String bookId, String extension) throws IOException {
        ensureDirectories();
        if (bookId == null || bookId.trim().isEmpty()) throw new IOException("Book ID 为空");
        String safeExt = (extension != null && !extension.isEmpty())
                ? (extension.startsWith(".") ? extension : "." + extension) : "";
        return new File(derivedDir, bookId.trim() + safeExt);
    }

    public File getCoversDir() {
        return coversDir;
    }

    public File getPagesCacheDir() {
        return pagesCacheDir;
    }

    public File createStagingFile(String prefix, String suffix) throws IOException {
        ensureDirectories();
        return File.createTempFile(prefix, suffix, stagingDir);
    }

    public File createStagingDirectory(String name) throws IOException {
        ensureDirectories();
        File dir = new File(stagingDir, name);
        assertPathInsideRoot(dir, stagingDir);
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IOException("Failed to create staging directory: " + dir.getAbsolutePath());
        }
        return dir;
    }

    public File getBookImportFile(String relativePath) throws IOException {
        if (relativePath == null || relativePath.trim().isEmpty()) throw new IOException("本地漫画文件路径为空");
        if (relativePath.startsWith("/") || relativePath.startsWith("\\")
                || relativePath.startsWith("file://") || new File(relativePath).isAbsolute()) {
            String path = relativePath.startsWith("file://") ? relativePath.substring(7) : relativePath;
            return new File(path);
        }
        File file = new File(importsDir, relativePath);
        assertPathInsideRoot(file, importsDir);
        if (file.getCanonicalFile().equals(importsDir.getCanonicalFile())) throw new IOException("本地漫画路径不能是整个书架目录");
        return file;
    }

    public File getCoverFile(String bookId) throws IOException {
        File file = new File(coversDir, bookId + ".jpg");
        assertPathInsideRoot(file, coversDir);
        return file;
    }

    public boolean promoteStagingToImports(File stagingFile, File targetImportFile) throws IOException {
        assertPathInsideRoot(stagingFile, stagingDir);
        assertPathInsideRoot(targetImportFile, importsDir);
        File parent = targetImportFile.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }
        if (targetImportFile.exists()) {
            throw new IOException("导入目标已存在，保留原副本: " + targetImportFile.getName());
        }
        boolean renamed = stagingFile.renameTo(targetImportFile);
        if (!renamed) {
            throw new IOException("无法将暂存文件移入本地书架");
        }
        return true;
    }

    public long getUsableSpace() {
        return libraryRoot.getUsableSpace();
    }

    public boolean hasSufficientSpace(long requiredBytes) {
        long usable = getUsableSpace();
        return (usable - requiredBytes) >= MIN_RESERVED_FREE_BYTES;
    }

    public boolean hasUsableMargin() {
        return getUsableSpace() >= MIN_RESERVED_FREE_BYTES;
    }

    public void checkUsableSpace(long requiredBytes) throws IOException {
        if (!hasSufficientSpace(requiredBytes)) {
            throw new IOException("存储空间不足，需预留至少 " + (MIN_RESERVED_FREE_BYTES / 1024 / 1024) + "MB 余量");
        }
    }

    public boolean hasSufficientSpaceForRemaining(long remainingBytes) {
        long usable = getUsableSpace();
        return (usable - Math.max(0L, remainingBytes)) >= MIN_RESERVED_FREE_BYTES;
    }

    public synchronized boolean deleteRecursively(File fileOrDir) {
        if (fileOrDir == null || !fileOrDir.exists()) return true;
        try {
            assertPathInsideRoot(fileOrDir, libraryRoot);
        } catch (IOException | SecurityException e) {
            return false;
        }
        if (fileOrDir.isDirectory()) {
            File[] files = fileOrDir.listFiles();
            if (files != null) {
                for (File child : files) {
                    deleteRecursively(child);
                }
            }
        }
        return fileOrDir.delete();
    }

    public void cleanStaging() {
        if (stagingDir.exists()) {
            File[] children = stagingDir.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
    }

    public synchronized void clearDerivedPagesCache() {
        if (pagesCacheDir.exists()) {
            File[] children = pagesCacheDir.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
    }

    public synchronized boolean clearDerivedPagesForBook(String bookId) {
        if (bookId == null || bookId.trim().isEmpty()) return true;
        File bookPagesDir = new File(pagesCacheDir, bookId.trim());
        return deleteRecursively(bookPagesDir);
    }

    public synchronized boolean deleteBookFiles(LocalModels.Book book) {
        boolean cleaned = clearDerivedPagesForBook(book.id);
        boolean isImportCopy = book.relativePath != null &&
                !book.relativePath.startsWith("/") &&
                !book.relativePath.startsWith("\\") &&
                !book.relativePath.startsWith("file://") &&
                !book.relativePath.startsWith("content://") &&
                !new File(book.relativePath).isAbsolute();
        if (LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) || isImportCopy) {
            try { cleaned &= deleteRecursively(getBookContentFile(book)); }
            catch (IOException | SecurityException error) { cleaned = false; }
        }
        try { cleaned &= deleteRecursively(getCoverFile(book.id)); }
        catch (IOException | SecurityException error) { cleaned = false; }
        if(book.coverPath!=null)cleaned &= deleteRecursively(new File(book.coverPath));
        File[] bookCovers=coversDir.listFiles();
        if(bookCovers!=null)for(File cover:bookCovers)if(cover.getName().startsWith(book.id+"_"))cleaned &= deleteRecursively(cover);
        try {
            if (importsDir.exists()) {
                File[] files = importsDir.listFiles();
                if (files != null) {
                    for (File f : files) {
                        if (f.getName().startsWith(book.id)) {
                            deleteRecursively(f);
                        }
                    }
                }
            }
            if (derivedDir.exists()) {
                File[] files = derivedDir.listFiles();
                if (files != null) {
                    for (File f : files) {
                        if (f.getName().startsWith(book.id)) {
                            deleteRecursively(f);
                        }
                    }
                }
            }
        } catch (Exception ignored) {}
        return cleaned;
    }

    public synchronized void cleanupOrphans(java.util.Set<String> activeRelativePaths, java.util.Set<String> activeCoverPaths) {
        cleanStaging();
        if (importsDir.exists()) {
            File[] files = importsDir.listFiles();
            if (files != null) {
                for (File f : files) {
                    if (activeRelativePaths == null || !activeRelativePaths.contains(f.getName())) {
                        deleteRecursively(f);
                    }
                }
            }
        }
        if (coversDir.exists()) {
            File[] covers = coversDir.listFiles();
            if (covers != null) {
                for (File c : covers) {
                    String fullPath = c.getAbsolutePath();
                    if (activeCoverPaths == null || (!activeCoverPaths.contains(fullPath) && !activeCoverPaths.contains(c.getName()))) {
                        c.delete();
                    }
                }
            }
        }
    }

    public synchronized void enforcePagesCacheLimit(long maxBytes) {
        if (!pagesCacheDir.exists()) return;
        List<File> allFiles = new ArrayList<>();
        collectAllFiles(pagesCacheDir, allFiles);
        long currentTotal = 0L;
        for (File f : allFiles) currentTotal += f.length();
        if (currentTotal <= maxBytes) return;

        Collections.sort(allFiles, (f1, f2) -> Long.compare(f1.lastModified(), f2.lastModified()));
        for (File f : allFiles) {
            long len = f.length();
            if (f.delete()) {
                currentTotal -= len;
                if (currentTotal <= maxBytes) break;
            }
        }
    }

    private void collectAllFiles(File dir, List<File> list) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                collectAllFiles(f, list);
            } else {
                String name = f.getName();
                if (name.endsWith(".writing") || name.endsWith(".tmp.writing")) {
                    continue;
                }
                list.add(f);
            }
        }
    }

    public long getImportsTotalSize() {
        return computeSize(importsDir);
    }

    public long getDerivedTotalSize() {
        return computeSize(derivedDir);
    }

    public long getTotalManagedSize() {
        return computeSize(libraryRoot);
    }

    private long computeSize(File dir) {
        if (dir == null || !dir.exists()) return 0L;
        if (!dir.isDirectory()) return dir.length();
        long total = 0L;
        File[] children = dir.listFiles();
        if (children != null) {
            for (File child : children) {
                total += computeSize(child);
            }
        }
        return total;
    }

    public static void assertPathInsideRoot(File target, File root) throws IOException {
        String canonicalTarget = target.getCanonicalPath();
        String canonicalRoot = root.getCanonicalPath();
        if (!canonicalTarget.equals(canonicalRoot) && !canonicalTarget.startsWith(canonicalRoot + File.separator)) {
            throw new SecurityException("Path traversal attempt detected: " + target.getAbsolutePath()
                    + " is outside " + root.getAbsolutePath());
        }
    }
}
