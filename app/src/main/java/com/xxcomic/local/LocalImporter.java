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
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class LocalImporter {
    public static final int MAX_FOLDER_DEPTH = 5;
    public static final int MAX_FOLDER_FILES = ArchiveIndex.MAX_ENTRIES;
    public static final long MAX_SINGLE_FILE_BYTES = ArchiveIndex.MAX_SINGLE_ENTRY_BYTES;
    public static final long MAX_TOTAL_BYTES = 20L * 1024L * 1024L * 1024L; // 20 GiB

    public static class ParsedName {
        public final String comicTitle;
        public final String chapterTitle;
        public final boolean matchedFormat;

        public ParsedName(String comicTitle, String chapterTitle, boolean matchedFormat) {
            this.comicTitle = comicTitle != null ? comicTitle : "";
            this.chapterTitle = chapterTitle != null ? chapterTitle : "";
            this.matchedFormat = matchedFormat;
        }
    }

    private static final Pattern TITLE_CHAPTER_PATTERN = Pattern.compile("^(.+?)\\s*[-—–]\\s*(.+)$");

    public static ParsedName parseTitleAndChapter(String fileName) {
        String base = stripExtension(fileName);
        if (base == null || base.trim().isEmpty()) {
            return new ParsedName("", "", false);
        }
        base = base.trim();
        Matcher m = TITLE_CHAPTER_PATTERN.matcher(base);
        if (m.matches()) {
            String comic = m.group(1).trim();
            String chapter = m.group(2).trim();
            if (!comic.isEmpty() && !chapter.isEmpty()) {
                return new ParsedName(comic, chapter, true);
            }
        }
        return new ParsedName(base, "全本", false);
    }

    private final Context context;
    private final LocalStorageManager storageManager;
    private final LocalLibraryStore store;

    public static class BoundedInputStream extends InputStream {
        private final InputStream in;
        private final long maxBytes;
        private final LocalModels.ImportProgressCallback callback;
        private long readBytes = 0;
        private boolean exceeded;

        public BoundedInputStream(InputStream in, long maxBytes) {
            this(in, maxBytes, null);
        }

        public BoundedInputStream(InputStream in, long maxBytes, LocalModels.ImportProgressCallback callback) {
            this.in = in;
            this.maxBytes = maxBytes;
            this.callback = callback;
        }

        @Override
        public int read() throws IOException {
            checkCancelled(callback);
            int b = in.read();
            if (b == -1) return -1;
            if (++readBytes > maxBytes) {
                exceeded = true;
                throw new IOException("读取大小超过上限: " + maxBytes);
            }
            return b;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            if (off < 0 || len < 0 || off > b.length - len) throw new IndexOutOfBoundsException();
            if (len == 0) return 0;
            checkCancelled(callback);
            if (readBytes >= maxBytes) return read();
            int toRead = (int) Math.min((long) len, maxBytes - readBytes);
            int n = in.read(b, off, toRead);
            if (n > 0) readBytes += n;
            return n;
        }

        @Override
        public void close() throws IOException {
            in.close();
            checkCancelled(callback);
            if (exceeded) throw new IOException("读取大小超过上限: " + maxBytes);
        }
    }

    static void checkCancelled(LocalModels.ImportProgressCallback callback) throws java.io.InterruptedIOException {
        if (Thread.currentThread().isInterrupted() || (callback != null && callback.isCancelled())) {
            throw new java.io.InterruptedIOException("已取消本地文件处理");
        }
    }

    public LocalImporter(Context context, LocalStorageManager storageManager, LocalLibraryStore store) {
        this.context = context.getApplicationContext();
        this.storageManager = storageManager;
        this.store = store;
    }

    public LocalModels.Book importArchiveUri(Uri uri, String rawDisplayName,
                                             LocalModels.ImportProgressCallback callback) throws Exception {
        return importArchiveOrVolume(uri, rawDisplayName, null, null, callback);
    }

    /** Parse an already downloaded private file without a second full-file copy or publishing early. */
    public static final class PreparedFile {
        public final LocalModels.Book book;
        public final ArchiveIndex.ParseResult index;
        PreparedFile(LocalModels.Book book, ArchiveIndex.ParseResult index) { this.book=book;this.index=index; }
    }

    public PreparedFile prepareDownloadedFile(File file, String bookId, String title, String format,
                                              String hash, File workDir, LocalModels.ImportProgressCallback callback) throws Exception {
        LocalStorageManager.assertPathInsideRoot(file,storageManager.getLibraryRoot());
        String path=file.getName();
        ArchiveIndex.ParseResult index;
        com.xxcomic.ebook.Publication publication=null;
        File archive=file;
        if(LocalModels.FORMAT_PDF.equals(format)) {
            index=com.xxcomic.pdf.PdfParser.parse(file,bookId,"全本",0,path,callback);
        } else if(LocalModels.FORMAT_EPUB.equals(format) || LocalModels.isKindleFormat(format)) {
            if(LocalModels.isKindleFormat(format)) {
                com.xxcomic.ebook.KindlePublicationAdapter.ParseResult kindle=
                        com.xxcomic.ebook.KindlePublicationAdapter.parse(file,bookId,workDir,callback);
                publication=kindle.publication;archive=kindle.derivedEpubFile;
            } else publication=com.xxcomic.ebook.EpubParser.parse(file);
            try(ZipFile zip=ArchiveIndex.openZipWithFallbackCharset(archive)) {
                index=publication.toParseResult(bookId,zip,new AndroidImageProbe(),null,0,path,callback);
            }
        } else index=ArchiveIndex.indexArchive(file,bookId,null,0,path,callback);
        checkCancelled(callback);
        if(index.chapters.isEmpty())throw new IOException("文件没有可阅读的内容");
        File cover=storageManager.getCoverFile(bookId+"_"+hash);
        String coverPath=null;
        if(LocalModels.FORMAT_PDF.equals(format)) {
            if(com.xxcomic.pdf.PdfParser.renderCover(file,cover))coverPath=cover.getAbsolutePath();
        } else if(extractArchiveCover(archive,index.candidateCoverEntries,cover,callback))coverPath=cover.getAbsolutePath();
        else if(publication!=null && com.xxcomic.ebook.TextReaderView.generateTextCover(title,publication.author,cover))coverPath=cover.getAbsolutePath();
        checkCancelled(callback);
        LocalModels.Book old=store.getBook(bookId);
        LocalLibraryStore.DeletedFingerprint deleted=store.findDeletedByFingerprint(bookId);
        // Unchanged content restores the same locator; changed content starts safely at its beginning.
        String progressKey=bookId+"_"+hash;
        long now=System.currentTimeMillis();
        LocalModels.Book book=new LocalModels.Book(bookId,bookId,title,old!=null?old.userTitle:deleted==null?null:deleted.userTitle,
                format,LocalModels.SOURCE_TYPE_FILE_DOWNLOAD,progressKey,path,coverPath,file.length(),index.chapters.size(),
                index.totalPages,LocalModels.STATUS_READY,old==null?now:old.createdAt,now);
        List<LocalModels.Chapter> versionChapters=new ArrayList<>();
        Map<String,List<LocalModels.Page>> versionPages=new HashMap<>();
        for(LocalModels.Chapter ch:index.chapters) {
            String chapterId=ch.id+"_"+hash;
            versionChapters.add(new LocalModels.Chapter(chapterId,bookId,ch.orderIndex,ch.title,ch.entryPath,ch.pageCount));
            List<LocalModels.Page> pages=new ArrayList<>();
            for(LocalModels.Page p:index.pagesByChapter.get(ch.id))pages.add(new LocalModels.Page(p.id+"_"+hash,bookId,chapterId,
                    p.orderIndex,p.entryPath,p.width,p.height,p.transformation,p.mimeType));
            versionPages.put(chapterId,pages);
        }
        index=new ArchiveIndex.ParseResult(versionChapters,versionPages,index.totalPages,index.totalUncompressedBytes,index.firstValidPageEntry,index.candidateCoverEntries);
        return new PreparedFile(book,index);
    }

    public LocalModels.Book importArchiveOrVolume(Uri uri, String rawDisplayName,
                                                  String explicitComicTitle, String explicitChapterTitle,
                                                  LocalModels.ImportProgressCallback callback) throws Exception {
        ContentResolver resolver = context.getContentResolver();
        String displayName = rawDisplayName;
        if (TextUtils.isEmpty(displayName)) {
            displayName = queryDisplayName(resolver, uri);
        }

        android.os.ParcelFileDescriptor[] outPfd = new android.os.ParcelFileDescriptor[1];
        File directFile = UriUtils.resolveDirectFile(context, uri);
        File sourceFile = null;
        boolean isZeroCopy = false;

        if (directFile != null && directFile.exists() && directFile.canRead()) {
            sourceFile = directFile;
            isZeroCopy = true;
        } else {
            File procFile = UriUtils.resolveFileOrProcFd(context, uri, outPfd);
            if (procFile != null && procFile.exists() && procFile.canRead()) {
                sourceFile = procFile;
                if (directFile != null) {
                    isZeroCopy = true;
                }
            }
        }

        File stagingFile = null;
        File targetImportFile = null;
        File coverTarget = null;
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");

        long fileSize = 0L;
        byte[] buffer = new byte[65536];

        try {
            if (isZeroCopy && sourceFile != null) {
                fileSize = sourceFile.length();
                long totalRead = 0L;
                try (InputStream in = new FileInputStream(sourceFile)) {
                    int len;
                    while ((len = in.read(buffer)) > 0) {
                        if (callback != null && callback.isCancelled()) {
                            throw new InterruptedException("用户取消导入");
                        }
                        sha256.update(buffer, 0, len);
                        totalRead += len;
                        if (callback != null) {
                            callback.onProgress(totalRead, fileSize, "正在校验文件: " + formatBytes(totalRead));
                        }
                    }
                }
            } else {
                stagingFile = storageManager.createStagingFile("import_zip_", ".tmp");
                try (InputStream in = resolver.openInputStream(uri);
                     OutputStream out = new FileOutputStream(stagingFile)) {
                    if (in == null) throw new IOException("无法打开所选文件数据流: " + uri);

                    int len;
                    while ((len = in.read(buffer)) > 0) {
                        if (callback != null && callback.isCancelled()) {
                            throw new InterruptedException("用户取消导入");
                        }
                        sha256.update(buffer, 0, len);
                        storageManager.checkUsableSpace(len);
                        out.write(buffer, 0, len);
                        fileSize += len;
                        if (callback != null) {
                            callback.onProgress(fileSize, -1L, "正在复制文件: " + formatBytes(fileSize));
                        }
                    }
                }
                sourceFile = stagingFile;
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            String fingerprint = toHexString(sha256.digest());

            // Check if active book with same fingerprint already exists
            LocalModels.Book existingSameFingerprint = store.findReadyByFingerprint(fingerprint);
            if (existingSameFingerprint != null) {
                if (stagingFile != null) storageManager.deleteRecursively(stagingFile);
                return existingSameFingerprint;
            }

            // Determine comic title and chapter title
            String resolvedComicTitle = explicitComicTitle;
            String resolvedChapterTitle = explicitChapterTitle;
            if (TextUtils.isEmpty(resolvedComicTitle)) {
                resolvedComicTitle = stripExtension(displayName);
            }
            if (TextUtils.isEmpty(resolvedComicTitle) || resolvedComicTitle.trim().isEmpty()) {
                resolvedComicTitle = "未命名漫画 " + store.getNextUnnamedIndex();
            } else {
                resolvedComicTitle = resolvedComicTitle.trim();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            if (callback != null) {
                callback.onProgress(fileSize, fileSize, "正在解析章节与页面...");
            }

            boolean isPdf = isPdfFile(sourceFile, displayName);
            boolean isEpub = !isPdf && isEpubFile(sourceFile, displayName);
            boolean isKindle = !isPdf && !isEpub && isKindleFile(sourceFile, displayName);
            String format;
            if (isPdf) {
                format = LocalModels.FORMAT_PDF;
            } else if (isEpub) {
                format = LocalModels.FORMAT_EPUB;
            } else if (isKindle) {
                String lower = (displayName != null ? displayName : sourceFile.getName()).toLowerCase(Locale.US);
                if (lower.endsWith(".azw3")) format = LocalModels.FORMAT_AZW3;
                else if (lower.endsWith(".azw")) format = LocalModels.FORMAT_AZW;
                else format = LocalModels.FORMAT_MOBI;
            } else if (displayName != null && displayName.toLowerCase(Locale.US).endsWith(".cbz")) {
                format = LocalModels.FORMAT_CBZ;
            } else {
                format = LocalModels.FORMAT_ZIP;
            }

            String ext;
            if (LocalModels.FORMAT_PDF.equals(format)) {
                ext = ".pdf";
            } else if (LocalModels.FORMAT_CBZ.equals(format)) {
                ext = ".cbz";
            } else if (LocalModels.FORMAT_EPUB.equals(format)) {
                ext = ".epub";
            } else if (LocalModels.FORMAT_AZW3.equals(format)) {
                ext = ".azw3";
            } else if (LocalModels.FORMAT_AZW.equals(format)) {
                ext = ".azw";
            } else if (LocalModels.FORMAT_MOBI.equals(format)) {
                ext = ".mobi";
            } else {
                ext = ".zip";
            }

            // Check if comic with same name already exists to merge / append
            if (explicitComicTitle != null && explicitChapterTitle != null) {
                LocalModels.Book existingBook = store.findReadyByTitle(resolvedComicTitle);
                if (existingBook != null && existingBook.format.equals(format)) {
                    String targetChapterTitle = resolvedChapterTitle;
                    if (TextUtils.isEmpty(targetChapterTitle)) {
                        targetChapterTitle = "第 " + (existingBook.chapterCount + 1) + " 话";
                    } else {
                        targetChapterTitle = targetChapterTitle.trim();
                    }

                    List<LocalModels.Chapter> existingChapters = store.getChapters(existingBook.id);
                    for (LocalModels.Chapter ch : existingChapters) {
                        if (ch.title.equals(targetChapterTitle)) {
                            if (stagingFile != null) storageManager.deleteRecursively(stagingFile);
                            throw new IOException("章节「" + targetChapterTitle + "」已存在于《" + existingBook.getDisplayTitle() + "》，已跳过");
                        }
                    }

                    int nextOrder = existingChapters.size();
                    String savedAppendPath;
                    if (isZeroCopy) {
                        savedAppendPath = directFile != null ? directFile.getAbsolutePath() : sourceFile.getAbsolutePath();
                    } else {
                        String targetFileName = existingBook.id + "_" + System.currentTimeMillis() + ext;
                        targetImportFile = storageManager.getBookImportFile(targetFileName);
                        savedAppendPath = targetFileName;
                    }

                    ArchiveIndex.ParseResult parseResult;
                    if (isPdf) {
                        parseResult = com.xxcomic.pdf.PdfParser.parse(sourceFile, existingBook.id, targetChapterTitle, nextOrder, savedAppendPath, callback);
                    } else if (isEpub) {
                        com.xxcomic.ebook.Publication pub = com.xxcomic.ebook.EpubParser.parse(sourceFile);
                        try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(sourceFile)) {
                            parseResult = pub.toParseResult(existingBook.id, zip, new AndroidImageProbe(), targetChapterTitle, nextOrder, savedAppendPath, callback);
                        }
                    } else if (isKindle) {
                        com.xxcomic.ebook.KindlePublicationAdapter.ParseResult kr = com.xxcomic.ebook.KindlePublicationAdapter.parse(sourceFile, existingBook.id, storageManager.getDerivedDir(), callback);
                        try (ZipFile derivedZip = ArchiveIndex.openZipWithFallbackCharset(kr.derivedEpubFile)) {
                            parseResult = kr.publication.toParseResult(existingBook.id, derivedZip, new AndroidImageProbe(), targetChapterTitle, nextOrder, savedAppendPath, callback);
                        }
                    } else {
                        parseResult = ArchiveIndex.indexArchive(sourceFile, existingBook.id, targetChapterTitle, nextOrder, savedAppendPath, callback);
                    }

                    if (callback != null && callback.isCancelled()) {
                        throw new InterruptedException("用户取消导入");
                    }

                    if (isZeroCopy) {
                        store.appendChapterToBook(existingBook.id, parseResult.chapters.get(0),
                                parseResult.pagesByChapter.get(parseResult.chapters.get(0).id), fileSize);
                    } else {
                        publishAppendChapter(stagingFile, targetImportFile, existingBook.id,
                                parseResult.chapters.get(0), parseResult.pagesByChapter.get(parseResult.chapters.get(0).id),
                                fileSize, callback);
                    }

                    return store.getBook(existingBook.id);
                }
            }

            // CREATE NEW COMIC
            LocalLibraryStore.DeletedFingerprint tombstone = store.findDeletedByFingerprint(fingerprint);
            String progressKey = (tombstone != null && tombstone.progressKey != null)
                    ? tombstone.progressKey
                    : LocalModels.buildStableBookId(fingerprint);
            String bookId = progressKey;
            String userTitle = tombstone != null ? tombstone.userTitle : null;
            ensureNoPendingImport(bookId);

            String savedRelativePath;
            if (isZeroCopy) {
                savedRelativePath = directFile != null ? directFile.getAbsolutePath() : sourceFile.getAbsolutePath();
            } else {
                String targetFileName = bookId + ext;
                targetImportFile = storageManager.getBookImportFile(targetFileName);
                savedRelativePath = targetFileName;
            }

            ArchiveIndex.ParseResult parseResult;
            com.xxcomic.ebook.Publication pub = null;
            com.xxcomic.ebook.KindlePublicationAdapter.ParseResult kindleResult = null;
            if (isPdf) {
                parseResult = com.xxcomic.pdf.PdfParser.parse(sourceFile, bookId, resolvedChapterTitle != null ? resolvedChapterTitle : "全本", 0, savedRelativePath, callback);
            } else if (isEpub) {
                pub = com.xxcomic.ebook.EpubParser.parse(sourceFile);
                try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(sourceFile)) {
                    parseResult = pub.toParseResult(bookId, zip, new AndroidImageProbe(), resolvedChapterTitle, 0, savedRelativePath, callback);
                }
            } else if (isKindle) {
                kindleResult = com.xxcomic.ebook.KindlePublicationAdapter.parse(sourceFile, bookId, storageManager.getDerivedDir(), callback);
                pub = kindleResult.publication;
                try (ZipFile derivedZip = ArchiveIndex.openZipWithFallbackCharset(kindleResult.derivedEpubFile)) {
                    parseResult = pub.toParseResult(bookId, derivedZip, new AndroidImageProbe(), resolvedChapterTitle, 0, savedRelativePath, callback);
                }
            } else {
                parseResult = ArchiveIndex.indexArchive(sourceFile, bookId, resolvedChapterTitle, 0, savedRelativePath, callback);
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Extract cover with candidate fallback
            String coverPath = null;
            coverTarget = storageManager.getCoverFile(bookId);
            if (isPdf) {
                if (com.xxcomic.pdf.PdfParser.renderCover(sourceFile, coverTarget)) {
                    coverPath = coverTarget.getAbsolutePath();
                }
            } else if (isKindle && kindleResult != null && kindleResult.coverBytes != null && kindleResult.coverBytes.length > 0) {
                try (FileOutputStream out = new FileOutputStream(coverTarget)) {
                    out.write(kindleResult.coverBytes);
                    coverPath = coverTarget.getAbsolutePath();
                } catch (Exception ignored) {}
            } else if (extractArchiveCover(sourceFile, parseResult.candidateCoverEntries, coverTarget, callback)) {
                coverPath = coverTarget.getAbsolutePath();
            } else if (isEpub || isKindle) {
                String author = (pub != null && pub.author != null) ? pub.author : (kindleResult != null ? kindleResult.author : "");
                if (com.xxcomic.ebook.TextReaderView.generateTextCover(resolvedComicTitle, author, coverTarget)) {
                    coverPath = coverTarget.getAbsolutePath();
                }
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, resolvedComicTitle, userTitle, format,
                    LocalModels.SOURCE_TYPE_IMPORT, progressKey, savedRelativePath,
                    coverPath, fileSize, parseResult.chapters.size(),
                    parseResult.totalPages, LocalModels.STATUS_READY,
                    System.currentTimeMillis(), System.currentTimeMillis()
            );

            if (isZeroCopy) {
                store.commitImport(book, parseResult.chapters, parseResult.pagesByChapter);
            } else {
                publishImport(stagingFile, targetImportFile, book, parseResult.chapters, parseResult.pagesByChapter, callback);
            }
            return book;
        } catch (Throwable error) {
            if (stagingFile != null) {
                storageManager.deleteRecursively(stagingFile);
            }
            if (coverTarget != null && coverTarget.exists()) {
                coverTarget.delete();
            }
            if (error instanceof Exception) throw (Exception) error;
            throw new IOException(error.getMessage(), error);
        } finally {
            if (outPfd[0] != null) {
                try { outPfd[0].close(); } catch (Exception ignored) {}
            }
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

        File directDir = UriUtils.resolveDirectFile(context, treeUri);
        boolean isZeroCopy = directDir != null && directDir.isDirectory() && directDir.canRead();

        File stagingDir = null;
        File targetImportDir = null;
        File coverTarget = null;
        File workDir = null;
        long totalFolderBytes = 0L;

        try {
            if (isZeroCopy) {
                workDir = directDir;
                if (callback != null) {
                    callback.onProgress(0, -1L, "正在扫描文件夹图片...");
                }
            } else {
                String stagingName = "import_folder_" + System.currentTimeMillis();
                stagingDir = storageManager.createStagingDirectory(stagingName);
                workDir = stagingDir;

                long[] bytesCopied = new long[]{0L};
                int[] fileCount = new int[]{0};
                copyDocumentTreeNative(treeUri, rootDocId, stagingDir, 0, fileCount, bytesCopied, callback);
                totalFolderBytes = bytesCopied[0];
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Index folder
            FolderIndexResult folderResult = indexFolder(workDir, callback);
            if (folderResult.validImages.isEmpty()) {
                throw new IOException("文件夹内没有找到可支持的漫画图片");
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            if (isZeroCopy) {
                for (String rel : folderResult.validImages) {
                    File img = new File(workDir, rel);
                    totalFolderBytes += img.length();
                }
            }

            String fingerprint = computeFolderManifestFingerprint(workDir, folderResult.validImages, callback);

            // Check if active book with same fingerprint already exists
            LocalModels.Book existing = store.findReadyByFingerprint(fingerprint);
            if (existing != null) {
                if (stagingDir != null) storageManager.deleteRecursively(stagingDir);
                return existing;
            }

            // Restore stable progressKey & userTitle from tombstone, or create stable id
            LocalLibraryStore.DeletedFingerprint tombstone = store.findDeletedByFingerprint(fingerprint);
            String progressKey = (tombstone != null && tombstone.progressKey != null)
                    ? tombstone.progressKey
                    : LocalModels.buildStableBookId(fingerprint);
            String bookId = progressKey;
            String userTitle = tombstone != null ? tombstone.userTitle : null;
            ensureNoPendingImport(bookId);

            String originalTitle = folderName != null ? folderName.trim() : "";
            if (TextUtils.isEmpty(originalTitle)) {
                originalTitle = "未命名漫画 " + store.getNextUnnamedIndex();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            if (callback != null) {
                callback.onProgress(totalFolderBytes, totalFolderBytes, "正在整理章节结构...");
            }

            FolderChaptersResult chaptersResult = buildFolderChapters(workDir, folderResult.validImages, bookId);

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            // Extract cover with candidate fallback
            String coverPath = null;
            coverTarget = storageManager.getCoverFile(bookId);
            if (extractFileCover(workDir, chaptersResult.candidateCoverEntries, coverTarget, callback)) {
                coverPath = coverTarget.getAbsolutePath();
            }

            if (callback != null && callback.isCancelled()) {
                throw new InterruptedException("用户取消导入");
            }

            String savedPath;
            if (isZeroCopy) {
                savedPath = directDir.getAbsolutePath();
            } else {
                targetImportDir = storageManager.getBookImportFile(bookId);
                savedPath = bookId;
            }

            LocalModels.Book book = new LocalModels.Book(
                    bookId, fingerprint, originalTitle, userTitle, LocalModels.FORMAT_FOLDER,
                    LocalModels.SOURCE_TYPE_IMPORT, progressKey, savedPath,
                    coverPath, totalFolderBytes, chaptersResult.chapters.size(),
                    chaptersResult.totalPages, LocalModels.STATUS_READY,
                    System.currentTimeMillis(), System.currentTimeMillis()
            );

            if (isZeroCopy) {
                store.commitImport(book, chaptersResult.chapters, chaptersResult.pagesByChapter);
            } else {
                publishImport(stagingDir, targetImportDir, book, chaptersResult.chapters, chaptersResult.pagesByChapter, callback);
            }
            return book;
        } catch (Throwable error) {
            if (stagingDir != null) {
                storageManager.deleteRecursively(stagingDir);
            }
            if (coverTarget != null && coverTarget.exists()) {
                coverTarget.delete();
            }
            if (error instanceof Exception) throw (Exception) error;
            throw new IOException(error.getMessage(), error);
        }
    }

    private void ensureNoPendingImport(String bookId) throws IOException {
        if (store.getBook(bookId) != null) throw new IOException("此漫画的上次文件处理尚未完成，请重启后重试");
    }

    private void publishImport(File staging, File target, LocalModels.Book book, List<LocalModels.Chapter> chapters,
                               Map<String, List<LocalModels.Page>> pages, LocalModels.ImportProgressCallback callback) throws Exception {
        synchronized (storageManager) {
            checkCancelled(callback);
            LocalModels.Book pending = store.getBook(book.id);
            if (pending != null) throw new IOException("此漫画的上次文件处理尚未完成，请重启后重试");
            store.commitImport(book.withStatus(LocalModels.STATUS_STAGING), Collections.emptyList(), Collections.emptyMap());
            try {
                storageManager.promoteStagingToImports(staging, target);
                checkCancelled(callback);
                store.commitImport(book, chapters, pages);
            } catch (Exception error) {
                if (storageManager.deleteBookFiles(book)) store.discardPendingImport(book.id);
                throw error;
            }
        }
    }

    private void publishAppendChapter(File staging, File target, String bookId,
                                      LocalModels.Chapter chapter, List<LocalModels.Page> pages,
                                      long fileSize, LocalModels.ImportProgressCallback callback) throws Exception {
        synchronized (storageManager) {
            checkCancelled(callback);
            storageManager.promoteStagingToImports(staging, target);
            try {
                checkCancelled(callback);
                store.appendChapterToBook(bookId, chapter, pages, fileSize);
            } catch (Exception error) {
                target.delete();
                throw error;
            }
        }
    }

    public static boolean isPdfFile(File file, String displayName) {
        return com.xxcomic.pdf.PdfParser.isPdfFile(file, displayName);
    }

    public static boolean isEpubFile(File file, String displayName) {
        if (displayName != null && displayName.toLowerCase(Locale.US).endsWith(".epub")) {
            return true;
        }
        try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(file)) {
            if (zip.getEntry("META-INF/container.xml") != null) {
                return true;
            }
            ZipEntry mime = zip.getEntry("mimetype");
            if (mime != null) {
                try (InputStream in = zip.getInputStream(mime)) {
                    byte[] b = new byte[32];
                    int n = in.read(b);
                    if (n > 0) {
                        String s = new String(b, 0, n, StandardCharsets.US_ASCII);
                        if (s.startsWith("application/epub+zip")) return true;
                    }
                }
            }
        } catch (Throwable ignored) {}
        return false;
    }

    public static boolean isKindleFile(File file, String displayName) {
        if (displayName != null) {
            String lower = displayName.toLowerCase(Locale.US);
            if (lower.endsWith(".mobi") || lower.endsWith(".azw") || lower.endsWith(".azw3")) {
                return true;
            }
        }
        if (file != null && file.exists() && file.length() >= 8) {
            try {
                com.xxcomic.ebook.KindleFormatDetector.DetectionResult r = com.xxcomic.ebook.KindleFormatDetector.detect(file);
                return r.variant == com.xxcomic.ebook.KindleFormatDetector.Variant.MOBI7
                        || r.variant == com.xxcomic.ebook.KindleFormatDetector.Variant.KF8
                        || r.variant == com.xxcomic.ebook.KindleFormatDetector.Variant.COMBO
                        || r.variant == com.xxcomic.ebook.KindleFormatDetector.Variant.PALMDOC
                        || r.variant == com.xxcomic.ebook.KindleFormatDetector.Variant.KFX
                        || r.variant == com.xxcomic.ebook.KindleFormatDetector.Variant.TOPAZ;
            } catch (Exception ignored) {}
        }
        return false;
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
        if (depth > MAX_FOLDER_DEPTH) throw new IOException("文件夹层级过深，请选择漫画所在的子文件夹");
        ContentResolver resolver = context.getContentResolver();
        Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId);

        String[] projection = new String[]{
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
        };

        byte[] buf = new byte[65536];

        try (Cursor cursor = resolver.query(childrenUri, projection, null, null, null)) {
            if (cursor == null) throw new IOException("无法读取文件夹内容，请重新选择");
            while (cursor.moveToNext()) {
                if (callback != null && callback.isCancelled()) {
                    throw new InterruptedException("用户取消导入");
                }
                String docId = cursor.getString(0);
                String name = cursor.getString(1);
                String mimeType = cursor.getString(2);

                if (name == null || ArchiveIndex.isIgnoredMetadata(name)) continue;
                String cleanName = sanitizeSegmentName(name);
                if (++fileCount[0] > MAX_FOLDER_FILES) {
                    throw new IOException("文件夹条目数量超过安全上限（最多 " + MAX_FOLDER_FILES + " 项）");
                }

                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mimeType)) {
                    File subDir = new File(targetDir, cleanName);
                    LocalStorageManager.assertPathInsideRoot(subDir, targetDir);
                    if (subDir.exists()) throw new IOException("文件夹包含重复名称: " + cleanName);
                    if (!subDir.exists() && !subDir.mkdirs()) {
                        throw new IOException("无法创建目录: " + subDir.getAbsolutePath());
                    }
                    copyDocumentTreeNative(treeUri, docId, subDir, depth + 1, fileCount, bytesCopied, callback);
                } else if (ArchiveIndex.hasImageExtension(cleanName)) {
                    File targetFile = new File(targetDir, cleanName);
                    LocalStorageManager.assertPathInsideRoot(targetFile, targetDir);
                    if (targetFile.exists()) throw new IOException("文件夹包含重复图片路径: " + cleanName);

                    Uri fileDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId);
                    try (InputStream in = resolver.openInputStream(fileDocUri);
                         OutputStream out = new FileOutputStream(targetFile)) {
                        if (in == null) throw new IOException("无法读取图片: " + cleanName);
                        long fileWritten = 0L;
                        int len;
                        while ((len = in.read(buf)) > 0) {
                            if (callback != null && callback.isCancelled()) {
                                throw new InterruptedException("用户取消导入");
                            }
                            fileWritten += len;
                            if (fileWritten > MAX_SINGLE_FILE_BYTES) {
                                throw new IOException("单张图片文件大小超出限制（最大 128MiB）: " + cleanName);
                            }
                            bytesCopied[0] += len;
                            if (bytesCopied[0] > MAX_TOTAL_BYTES) {
                                throw new IOException("文件夹解压总大小超出上限（最大 20GiB）");
                            }
                            storageManager.checkUsableSpace(len);
                            out.write(buf, 0, len);
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
        return indexFolder(rootDir, null);
    }

    public static FolderIndexResult indexFolder(File rootDir, LocalModels.ImportProgressCallback callback) throws IOException {
        return indexFolder(rootDir, callback, new AndroidImageProbe());
    }

    static FolderIndexResult indexFolder(File rootDir, LocalModels.ImportProgressCallback callback,
                                         ArchiveIndex.ImageProbe probe) throws IOException {
        List<String> found = new ArrayList<>();
        collectImagesRecursive(rootDir, "", found, 0, callback, probe);
        if (found.isEmpty()) {
            throw new IOException("未找到有效的漫画图片: " + rootDir.getAbsolutePath());
        }
        return new FolderIndexResult(found);
    }

    private static void collectImagesRecursive(File current, String prefix, List<String> result, int depth, LocalModels.ImportProgressCallback callback,
                                               ArchiveIndex.ImageProbe probe) throws IOException {
        if (callback != null && callback.isCancelled()) {
            throw new IOException("用户取消导入");
        }
        if (depth > MAX_FOLDER_DEPTH) {
            throw new IOException("目录层级过深（最多支持 5 层）: " + current.getAbsolutePath());
        }
        File[] children = current.listFiles();
        if (children == null) return;
        for (File child : children) {
            if (callback != null && callback.isCancelled()) {
                throw new IOException("用户取消导入");
            }
            String name = child.getName();
            if (ArchiveIndex.isIgnoredMetadata(name)) continue;
            String rel = prefix.isEmpty() ? name : prefix + "/" + name;
            if (child.isDirectory()) {
                collectImagesRecursive(child, rel, result, depth + 1, callback, probe);
            } else if (ArchiveIndex.hasImageExtension(name)) {
                if (ArchiveIndex.isDecodableImage(() -> new FileInputStream(child), callback, probe)) {
                    result.add(rel.replace('\\', '/'));
                }
            }
        }
    }

    public static String computeFolderManifestFingerprint(File rootDir, List<String> imageRelPaths) throws Exception {
        return computeFolderManifestFingerprint(rootDir, imageRelPaths, null);
    }

    public static String computeFolderManifestFingerprint(File rootDir, List<String> imageRelPaths, LocalModels.ImportProgressCallback callback) throws Exception {
        List<String> sorted = new ArrayList<>(imageRelPaths);
        Collections.sort(sorted, new NaturalPathOrder());

        MessageDigest manifestDigest = MessageDigest.getInstance("SHA-256");
        byte[] buf = new byte[65536];

        for (String rel : sorted) {
            if (callback != null && callback.isCancelled()) {
                throw new IOException("用户取消导入");
            }
            File img = new File(rootDir, rel);
            MessageDigest fileDigest = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new FileInputStream(img)) {
                int len;
                while ((len = in.read(buf)) > 0) {
                    if (callback != null && callback.isCancelled()) {
                        throw new IOException("用户取消导入");
                    }
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

    static boolean extractArchiveCover(File zipFile, List<String> candidateEntries, File targetCoverFile, LocalModels.ImportProgressCallback callback) {
        if (candidateEntries == null || candidateEntries.isEmpty()) return false;
        try (ZipFile zip = ArchiveIndex.openZipWithFallbackCharset(zipFile)) {
            for (String entryName : candidateEntries) {
                if (callback != null && callback.isCancelled()) return false;
                ZipEntry entry = zip.getEntry(entryName);
                if (entry == null) continue;

                BitmapFactory.Options bounds = new BitmapFactory.Options();
                bounds.inJustDecodeBounds = true;
                try (InputStream in = new BoundedInputStream(zip.getInputStream(entry), ArchiveIndex.MAX_PAGE_BYTES, callback)) {
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
                try (InputStream in = new BoundedInputStream(zip.getInputStream(entry), ArchiveIndex.MAX_PAGE_BYTES, callback)) {
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

    private boolean extractFileCover(File rootDir, List<String> candidatePaths, File targetCoverFile,
                                     LocalModels.ImportProgressCallback callback) throws IOException {
        if (candidatePaths == null || candidatePaths.isEmpty()) return false;
        for (String relPath : candidatePaths) {
            checkCancelled(callback);
            File file = new File(rootDir, relPath);
            if (!file.exists() || file.length() < 32) continue;

            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            try (InputStream in = new BoundedInputStream(new FileInputStream(file), ArchiveIndex.MAX_PAGE_BYTES, callback)) {
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
            try (InputStream in = new BoundedInputStream(new FileInputStream(file), ArchiveIndex.MAX_PAGE_BYTES, callback)) {
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
