package com.xxcomic.local;

import java.io.Serializable;

public final class LocalModels {
    private LocalModels() {
    }

    public static final String STATUS_READY = "ready";
    public static final String STATUS_STAGING = "staging";
    public static final String STATUS_DELETING = "deleting";
    public static final String STATUS_FAILED = "failed";

    public static final String FORMAT_ZIP = "zip";
    public static final String FORMAT_CBZ = "cbz";
    public static final String FORMAT_FOLDER = "folder";
    public static final String FORMAT_EPUB = "epub";

    public static final String SOURCE_TYPE_IMPORT = "import";
    public static final String SOURCE_TYPE_DOWNLOAD = "download";

    public static final class Book implements Serializable {
        private static final long serialVersionUID = 1L;

        public final String id;
        public final String fingerprint;
        public final String originalTitle;
        public final String userTitle;
        public final String format;
        public final String sourceType;
        public final String progressKey;
        public final String relativePath;
        public final String coverPath;
        public final long totalSize;
        public final int chapterCount;
        public final int pageCount;
        public final String status;
        public final long createdAt;
        public final long updatedAt;

        public Book(String id, String fingerprint, String originalTitle, String userTitle,
                    String format, String sourceType, String progressKey, String relativePath,
                    String coverPath, long totalSize, int chapterCount, int pageCount,
                    String status, long createdAt, long updatedAt) {
            this.id = id;
            this.fingerprint = fingerprint;
            this.originalTitle = originalTitle != null ? originalTitle : "";
            this.userTitle = userTitle;
            this.format = format != null ? format : FORMAT_ZIP;
            this.sourceType = sourceType != null ? sourceType : SOURCE_TYPE_IMPORT;
            this.progressKey = progressKey != null ? progressKey : id;
            this.relativePath = relativePath != null ? relativePath : "";
            this.coverPath = coverPath;
            this.totalSize = Math.max(0L, totalSize);
            this.chapterCount = Math.max(0, chapterCount);
            this.pageCount = Math.max(0, pageCount);
            this.status = status != null ? status : STATUS_READY;
            this.createdAt = createdAt;
            this.updatedAt = updatedAt;
        }

        public String getDisplayTitle() {
            if (userTitle != null && !userTitle.trim().isEmpty()) {
                return userTitle.trim();
            }
            if (originalTitle != null && !originalTitle.trim().isEmpty()) {
                return originalTitle.trim();
            }
            return "未命名漫画";
        }

        public Book withUserTitle(String newUserTitle) {
            return new Book(id, fingerprint, originalTitle, newUserTitle, format, sourceType,
                    progressKey, relativePath, coverPath, totalSize, chapterCount, pageCount,
                    status, createdAt, System.currentTimeMillis());
        }

        public Book withStatus(String newStatus) {
            return new Book(id, fingerprint, originalTitle, userTitle, format, sourceType,
                    progressKey, relativePath, coverPath, totalSize, chapterCount, pageCount,
                    newStatus, createdAt, System.currentTimeMillis());
        }
    }

    public static final class Chapter implements Serializable {
        private static final long serialVersionUID = 1L;

        public final String id;
        public final String bookId;
        public final int orderIndex;
        public final String title;
        public final String entryPath;
        public final int pageCount;

        public Chapter(String id, String bookId, int orderIndex, String title,
                       String entryPath, int pageCount) {
            this.id = id;
            this.bookId = bookId;
            this.orderIndex = orderIndex;
            this.title = title != null ? title : "";
            this.entryPath = entryPath != null ? entryPath : "";
            this.pageCount = Math.max(0, pageCount);
        }
    }

    public static final class Page implements Serializable {
        private static final long serialVersionUID = 1L;

        public final String id;
        public final String bookId;
        public final String chapterId;
        public final int orderIndex;
        public final String entryPath;
        public final int width;
        public final int height;
        public final String transformation;
        public final String mimeType;

        public Page(String id, String bookId, String chapterId, int orderIndex,
                    String entryPath, int width, int height, String transformation,
                    String mimeType) {
            this.id = id;
            this.bookId = bookId;
            this.chapterId = chapterId;
            this.orderIndex = orderIndex;
            this.entryPath = entryPath != null ? entryPath : "";
            this.width = Math.max(0, width);
            this.height = Math.max(0, height);
            this.transformation = transformation;
            this.mimeType = mimeType != null ? mimeType : "image/jpeg";
        }
    }

    public static String buildStableBookId(String fingerprint) {
        if (fingerprint == null) return "local_unknown";
        return "local_" + fingerprint;
    }

    public static String buildStableChapterId(String bookIdOrProgressKey, int orderIndex) {
        return bookIdOrProgressKey + "_ch_" + orderIndex;
    }

    public static String buildStablePageId(String chapterId, int orderIndex) {
        return chapterId + "_p_" + orderIndex;
    }

    public interface ImportProgressCallback {
        void onProgress(long currentBytes, long totalBytes, String message);
        boolean isCancelled();
    }
}
