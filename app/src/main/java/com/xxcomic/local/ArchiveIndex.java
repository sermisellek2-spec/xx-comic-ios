package com.xxcomic.local;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class ArchiveIndex {
    public static final int MAX_ENTRIES = 50000;
    public static final long MAX_SINGLE_ENTRY_BYTES = 128L * 1024L * 1024L; // 128 MiB
    public static final long MAX_TOTAL_UNCOMPRESSED_BYTES = 20L * 1024L * 1024L * 1024L; // 20 GiB

    public static class ParseResult {
        public final List<LocalModels.Chapter> chapters;
        public final Map<String, List<LocalModels.Page>> pagesByChapter;
        public final int totalPages;
        public final long totalUncompressedBytes;
        public final String firstValidPageEntry;

        public ParseResult(List<LocalModels.Chapter> chapters,
                           Map<String, List<LocalModels.Page>> pagesByChapter,
                           int totalPages, long totalUncompressedBytes,
                           String firstValidPageEntry) {
            this.chapters = chapters;
            this.pagesByChapter = pagesByChapter;
            this.totalPages = totalPages;
            this.totalUncompressedBytes = totalUncompressedBytes;
            this.firstValidPageEntry = firstValidPageEntry;
        }
    }

    private static class ValidEntry {
        final String rawEntryName;
        final String strippedPath;
        final long size;
        final String mimeType;

        ValidEntry(String rawEntryName, String strippedPath, long size, String mimeType) {
            this.rawEntryName = rawEntryName;
            this.strippedPath = strippedPath;
            this.size = size;
            this.mimeType = mimeType;
        }
    }

    public static ParseResult indexArchive(File archiveFile, String bookId) throws IOException {
        ZipFile zipFile = openZipWithFallbackCharset(archiveFile);
        try {
            return indexZipFile(zipFile, bookId);
        } finally {
            try {
                zipFile.close();
            } catch (IOException ignored) {}
        }
    }

    public static ZipFile openZipWithFallbackCharset(File file) throws IOException {
        ZipFile zipFile = null;
        try {
            zipFile = new ZipFile(file, StandardCharsets.UTF_8);
            Enumeration<? extends ZipEntry> entries = zipFile.entries();
            while (entries.hasMoreElements()) {
                entries.nextElement().getName();
            }
            return zipFile;
        } catch (Exception utf8Error) {
            if (zipFile != null) {
                try {
                    zipFile.close();
                } catch (IOException ignored) {}
            }
            try {
                ZipFile fallbackZip = new ZipFile(file, Charset.forName("GB18030"));
                Enumeration<? extends ZipEntry> entries = fallbackZip.entries();
                while (entries.hasMoreElements()) {
                    entries.nextElement().getName();
                }
                return fallbackZip;
            } catch (Exception gbError) {
                throw new IOException("无法解析压缩包，UTF-8 与 GB18030 编码均解析失败: " + utf8Error.getMessage(), utf8Error);
            }
        }
    }

    private static ParseResult indexZipFile(ZipFile zipFile, String bookId) throws IOException {
        Enumeration<? extends ZipEntry> entries = zipFile.entries();
        int count = 0;
        long totalBytes = 0;

        List<RawEntryInfo> candidateEntries = new ArrayList<>();

        while (entries.hasMoreElements()) {
            ZipEntry entry = entries.nextElement();
            count++;
            if (count > MAX_ENTRIES) {
                throw new IOException("压缩包条目数量超过安全上限（最多 " + MAX_ENTRIES + " 个条目）");
            }

            long entrySize = entry.getSize();
            if (entrySize > MAX_SINGLE_ENTRY_BYTES) {
                throw new IOException("压缩包单文件大小超过限制（" + entry.getName() + " 大小超过 128MiB）");
            }
            if (entrySize > 0) {
                totalBytes += entrySize;
                if (totalBytes > MAX_TOTAL_UNCOMPRESSED_BYTES) {
                    throw new IOException("压缩包总解压预算超过上限（超过 20GiB）");
                }
            }

            if (entry.isDirectory()) continue;

            String name = entry.getName();
            validateEntryPath(name);

            if (isIgnoredMetadata(name)) continue;

            if (hasImageExtension(name)) {
                candidateEntries.add(new RawEntryInfo(name, entrySize));
            }
        }

        if (candidateEntries.isEmpty()) {
            throw new IOException("压缩包内没有找到可支持的漫画图片");
        }

        // Verify magic bytes
        List<RawEntryInfo> verifiedEntries = new ArrayList<>();
        Map<String, String> mimeTypes = new HashMap<>();

        for (RawEntryInfo item : candidateEntries) {
            ZipEntry entry = zipFile.getEntry(item.name);
            if (entry == null) continue;
            byte[] header = new byte[16];
            int readBytes = 0;
            try (InputStream in = zipFile.getInputStream(entry)) {
                readBytes = in.read(header);
            } catch (Exception e) {
                continue;
            }
            if (readBytes >= 4 && isImageMagic(header, readBytes)) {
                verifiedEntries.add(item);
                mimeTypes.put(item.name, detectMimeType(header, readBytes, item.name));
            }
        }

        if (verifiedEntries.isEmpty()) {
            throw new IOException("压缩包内图片文件损坏或非有效图片格式");
        }

        // Strip single wrapper directory layers
        List<String> rawPaths = new ArrayList<>();
        for (RawEntryInfo item : verifiedEntries) {
            rawPaths.add(normalizePath(item.name));
        }

        String wrapperPrefix = findCommonWrapperPrefix(rawPaths);

        List<ValidEntry> validList = new ArrayList<>();
        for (RawEntryInfo item : verifiedEntries) {
            String norm = normalizePath(item.name);
            String stripped = norm;
            if (!wrapperPrefix.isEmpty() && norm.startsWith(wrapperPrefix)) {
                stripped = norm.substring(wrapperPrefix.length());
            }
            validList.add(new ValidEntry(item.name, stripped, item.size, mimeTypes.get(item.name)));
        }

        // Sort by NaturalPathOrder of stripped path
        Collections.sort(validList, (a, b) -> new NaturalPathOrder().compare(a.strippedPath, b.strippedPath));

        // Group into chapters
        List<ValidEntry> rootImages = new ArrayList<>();
        Map<String, List<ValidEntry>> subFolders = new LinkedHashMap<>();

        for (ValidEntry entry : validList) {
            int slashIndex = entry.strippedPath.indexOf('/');
            if (slashIndex < 0) {
                rootImages.add(entry);
            } else {
                String firstSeg = entry.strippedPath.substring(0, slashIndex);
                List<ValidEntry> group = subFolders.get(firstSeg);
                if (group == null) {
                    group = new ArrayList<>();
                    subFolders.put(firstSeg, group);
                }
                group.add(entry);
            }
        }

        List<LocalModels.Chapter> chapters = new ArrayList<>();
        Map<String, List<LocalModels.Page>> pagesByChapter = new HashMap<>();
        int chapterOrder = 0;

        if (subFolders.isEmpty()) {
            // Flat images: exactly 1 chapter titled "正文"
            String chapterId = bookId + "_ch_0";
            LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, 0, "正文", "", rootImages.size());
            chapters.add(ch);

            List<LocalModels.Page> pageList = new ArrayList<>();
            for (int i = 0; i < rootImages.size(); i++) {
                ValidEntry v = rootImages.get(i);
                String pageId = chapterId + "_p_" + i;
                pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.rawEntryName, 0, 0, null, v.mimeType));
            }
            pagesByChapter.put(chapterId, pageList);
        } else {
            // If both root images and chapters exist: root images become "未分章"
            if (!rootImages.isEmpty()) {
                String chapterId = bookId + "_ch_" + (chapterOrder++);
                LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, chapters.size(), "未分章", "", rootImages.size());
                chapters.add(ch);

                List<LocalModels.Page> pageList = new ArrayList<>();
                for (int i = 0; i < rootImages.size(); i++) {
                    ValidEntry v = rootImages.get(i);
                    String pageId = chapterId + "_p_" + i;
                    pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.rawEntryName, 0, 0, null, v.mimeType));
                }
                pagesByChapter.put(chapterId, pageList);
            }

            // Sort chapter folder names naturally
            List<String> folderNames = new ArrayList<>(subFolders.keySet());
            Collections.sort(folderNames, new NaturalPathOrder());

            for (String folderName : folderNames) {
                List<ValidEntry> entriesInFolder = subFolders.get(folderName);
                String chapterId = bookId + "_ch_" + (chapterOrder++);
                LocalModels.Chapter ch = new LocalModels.Chapter(chapterId, bookId, chapters.size(), folderName, folderName, entriesInFolder.size());
                chapters.add(ch);

                List<LocalModels.Page> pageList = new ArrayList<>();
                for (int i = 0; i < entriesInFolder.size(); i++) {
                    ValidEntry v = entriesInFolder.get(i);
                    String pageId = chapterId + "_p_" + i;
                    pageList.add(new LocalModels.Page(pageId, bookId, chapterId, i, v.rawEntryName, 0, 0, null, v.mimeType));
                }
                pagesByChapter.put(chapterId, pageList);
            }
        }

        String firstValidPage = validList.get(0).rawEntryName;
        return new ParseResult(chapters, pagesByChapter, validList.size(), totalBytes, firstValidPage);
    }

    private static String findCommonWrapperPrefix(List<String> paths) {
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

    public static void validateEntryPath(String name) throws IOException {
        String norm = name.replace('\\', '/');
        if (norm.startsWith("/") || norm.contains("../") || norm.contains("/..") || norm.equals("..")) {
            throw new SecurityException("非法路径穿越条目: " + name);
        }
        // Check Windows drive letters like C:
        if (norm.length() >= 2 && norm.charAt(1) == ':' && Character.isLetter(norm.charAt(0))) {
            throw new SecurityException("非法绝对盘符路径条目: " + name);
        }
    }

    public static boolean isIgnoredMetadata(String name) {
        String lower = name.toLowerCase(Locale.US);
        if (lower.contains("__macosx/") || lower.contains("/__macosx/")) return true;
        if (lower.endsWith(".ds_store") || lower.endsWith("thumbs.db")
                || lower.endsWith(".nomedia") || lower.endsWith("desktop.ini")) {
            return true;
        }
        return false;
    }

    public static boolean hasImageExtension(String name) {
        String lower = name.toLowerCase(Locale.US);
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg")
                || lower.endsWith(".png") || lower.endsWith(".webp")
                || lower.endsWith(".gif");
    }

    public static boolean isImageMagic(byte[] header, int length) {
        if (header == null || length < 4) return false;
        // JPEG: FF D8 FF
        if ((header[0] & 0xFF) == 0xFF && (header[1] & 0xFF) == 0xD8 && (header[2] & 0xFF) == 0xFF) {
            return true;
        }
        // PNG: 89 50 4E 47
        if ((header[0] & 0xFF) == 0x89 && header[1] == 'P' && header[2] == 'N' && header[3] == 'G') {
            return true;
        }
        // GIF: GIF8
        if (header[0] == 'G' && header[1] == 'I' && header[2] == 'F' && header[3] == '8') {
            return true;
        }
        // WebP: RIFF .... WEBP
        if (length >= 12 && header[0] == 'R' && header[1] == 'I' && header[2] == 'F' && header[3] == 'F'
                && header[8] == 'W' && header[9] == 'E' && header[10] == 'B' && header[11] == 'P') {
            return true;
        }
        return false;
    }

    public static String detectMimeType(byte[] header, int length, String name) {
        if (header != null && length >= 3) {
            if ((header[0] & 0xFF) == 0xFF && (header[1] & 0xFF) == 0xD8 && (header[2] & 0xFF) == 0xFF) {
                return "image/jpeg";
            }
            if (length >= 4 && (header[0] & 0xFF) == 0x89 && header[1] == 'P' && header[2] == 'N' && header[3] == 'G') {
                return "image/png";
            }
            if (length >= 4 && header[0] == 'G' && header[1] == 'I' && header[2] == 'F') {
                return "image/gif";
            }
            if (length >= 12 && header[0] == 'R' && header[1] == 'I' && header[2] == 'F' && header[3] == 'F'
                    && header[8] == 'W' && header[9] == 'E' && header[10] == 'B' && header[11] == 'P') {
                return "image/webp";
            }
        }
        String lower = name.toLowerCase(Locale.US);
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".webp")) return "image/webp";
        if (lower.endsWith(".gif")) return "image/gif";
        return "image/jpeg";
    }

    private static String normalizePath(String path) {
        String s = path.replace('\\', '/');
        while (s.startsWith("/")) s = s.substring(1);
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        return s;
    }

    private static class RawEntryInfo {
        final String name;
        final long size;

        RawEntryInfo(String name, long size) {
            this.name = name;
            this.size = size;
        }
    }
}
