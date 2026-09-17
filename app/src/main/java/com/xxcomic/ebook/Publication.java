package com.xxcomic.ebook;

import com.xxcomic.local.ArchiveIndex;
import com.xxcomic.local.LocalModels;

import java.io.File;
import java.io.IOException;
import java.io.Serializable;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class Publication implements Serializable {
    private static final long serialVersionUID = 1L;

    private static final Pattern PSEUDO_PAGE_PATTERN = Pattern.compile(
            "^(?:第\\s*)?\\d+\\s*[页頁]$|^(?:page|p)\\s*#?\\s*\\d+(?:\\.(?:xhtml|html|jpg|jpeg|png))?$|^\\d+$",
            Pattern.CASE_INSENSITIVE
    );

    public static boolean isPseudoPageNav(List<NavItem> navList, int spineSize) {
        if (navList == null || navList.isEmpty()) return false;
        int pageMatchCount = 0;
        for (NavItem nav : navList) {
            String t = nav.title != null ? nav.title.trim() : "";
            if (PSEUDO_PAGE_PATTERN.matcher(t).matches()) {
                pageMatchCount++;
            }
        }
        return (pageMatchCount * 2 >= navList.size()) ||
                (spineSize > 0 && navList.size() >= spineSize * 0.7 && pageMatchCount >= 2);
    }

    public static class ManifestItem implements Serializable {
        private static final long serialVersionUID = 1L;
        public final String id;
        public final String href;
        public final String mediaType;
        public final String properties;

        public ManifestItem(String id, String href, String mediaType, String properties) {
            this.id = id != null ? id : "";
            this.href = href != null ? href : "";
            this.mediaType = mediaType != null ? mediaType : "";
            this.properties = properties != null ? properties : "";
        }
    }

    public static class SpineItem implements Serializable {
        private static final long serialVersionUID = 1L;
        public final String idref;
        public final String fullZipPath;
        public final String mediaType;
        public final boolean linear;
        public final String resolvedImageEntry;

        public SpineItem(String idref, String fullZipPath, String mediaType, boolean linear, String resolvedImageEntry) {
            this.idref = idref != null ? idref : "";
            this.fullZipPath = fullZipPath != null ? fullZipPath : "";
            this.mediaType = mediaType != null ? mediaType : "";
            this.linear = linear;
            this.resolvedImageEntry = resolvedImageEntry;
        }

        public boolean isImageOrImageWrapper() {
            return resolvedImageEntry != null && !resolvedImageEntry.isEmpty();
        }
    }

    public static class NavItem implements Serializable {
        private static final long serialVersionUID = 1L;
        public final String title;
        public final String href;
        public final int spineIndex;
        public final List<NavItem> children;

        public NavItem(String title, String href, int spineIndex, List<NavItem> children) {
            this.title = title != null ? title : "";
            this.href = href != null ? href : "";
            this.spineIndex = spineIndex;
            this.children = children != null ? children : Collections.emptyList();
        }
    }

    private static class ChapterBoundary {
        final String title;
        final int startIndex;

        ChapterBoundary(String title, int startIndex) {
            this.title = title;
            this.startIndex = startIndex;
        }
    }

    public final String title;
    public final String author;
    public final String description;
    public final String language;
    public final String opfPath;
    public final String coverEntry;
    public final List<SpineItem> spine;
    public final List<NavItem> navItems;
    public final Map<String, ManifestItem> manifest;
    public final boolean isFixedLayout;
    public final boolean isPurePictureEpub;
    public final boolean isReflowableText;
    public final boolean hasDrm;
    public final boolean hasFontObfuscation;
    public final String unsupportedReason;

    public Publication(String title, String author, String description, String language,
                       String opfPath, String coverEntry,
                       List<SpineItem> spine, List<NavItem> navItems,
                       Map<String, ManifestItem> manifest,
                       boolean isFixedLayout, boolean isPurePictureEpub,
                       boolean isReflowableText, boolean hasDrm,
                       boolean hasFontObfuscation, String unsupportedReason) {
        this.title = title;
        this.author = author;
        this.description = description;
        this.language = language;
        this.opfPath = opfPath;
        this.coverEntry = coverEntry;
        this.spine = spine != null ? Collections.unmodifiableList(new ArrayList<>(spine)) : Collections.emptyList();
        this.navItems = navItems != null ? Collections.unmodifiableList(new ArrayList<>(navItems)) : Collections.emptyList();
        this.manifest = manifest != null ? Collections.unmodifiableMap(new LinkedHashMap<>(manifest)) : Collections.emptyMap();
        this.isFixedLayout = isFixedLayout;
        this.isPurePictureEpub = isPurePictureEpub;
        this.isReflowableText = isReflowableText;
        this.hasDrm = hasDrm;
        this.hasFontObfuscation = hasFontObfuscation;
        this.unsupportedReason = unsupportedReason;
    }

    private static void collectNavPoints(List<NavItem> items, List<NavItem> out) {
        if (items == null) return;
        for (NavItem item : items) {
            if (item.spineIndex >= 0) {
                out.add(item);
            }
            if (item.children != null && !item.children.isEmpty()) {
                collectNavPoints(item.children, out);
            }
        }
    }

    public ArchiveIndex.ParseResult toParseResult(String bookId, ZipFile zipFile,
                                                  ArchiveIndex.ImageProbe probe,
                                                  LocalModels.ImportProgressCallback callback) throws IOException {
        return toParseResult(bookId, zipFile, probe, null, 0, null, callback);
    }

    public ArchiveIndex.ParseResult toParseResult(String bookId, ZipFile zipFile,
                                                  ArchiveIndex.ImageProbe probe,
                                                  String overrideChapterTitle,
                                                  int chapterOrderOffset,
                                                  String chapterEntryPath,
                                                  LocalModels.ImportProgressCallback callback) throws IOException {
        if (hasDrm) {
            throw new IOException("该 EPUB 受到 DRM 加密保护，暂不支持阅读");
        }
        if (spine.isEmpty()) {
            throw new IOException("EPUB 没有可阅读的正文页面");
        }

        List<LocalModels.Chapter> chapters = new ArrayList<>();
        Map<String, List<LocalModels.Page>> pagesByChapter = new LinkedHashMap<>();

        List<ChapterBoundary> boundaries = new ArrayList<>();

        if (overrideChapterTitle != null && !overrideChapterTitle.trim().isEmpty()) {
            // Explicit chapter title: the whole volume file forms a single chapter
            boundaries.add(new ChapterBoundary(overrideChapterTitle.trim(), 0));
        } else {
            List<NavItem> mappedNav = new ArrayList<>();
            collectNavPoints(navItems, mappedNav);
            Collections.sort(mappedNav, (a, b) -> Integer.compare(a.spineIndex, b.spineIndex));

            if (isPseudoPageNav(mappedNav, spine.size())) {
                // Pseudo-page directory detected (e.g. 第001页, 第002页... in comic EPUB)
                // Collapse into a single chapter containing all pages
                String chTitle = (title != null && !title.trim().isEmpty()) ? title.trim() : "全本";
                boundaries.add(new ChapterBoundary(chTitle, 0));
            } else {
                for (NavItem nav : mappedNav) {
                    if (nav.spineIndex >= 0 && nav.spineIndex < spine.size()) {
                        if (boundaries.isEmpty() || boundaries.get(boundaries.size() - 1).startIndex < nav.spineIndex) {
                            boundaries.add(new ChapterBoundary(nav.title, nav.spineIndex));
                        }
                    }
                }

                if (boundaries.isEmpty()) {
                    String chTitle = (title != null && !title.trim().isEmpty()) ? title.trim() : "全 1 卷";
                    boundaries.add(new ChapterBoundary(chTitle, 0));
                } else if (boundaries.get(0).startIndex > 0) {
                    boundaries.add(0, new ChapterBoundary("封面与序言", 0));
                }
            }
        }

        int totalPages = 0;
        long totalBytes = 0;
        String firstValidPageEntry = null;

        for (int chIdx = 0; chIdx < boundaries.size(); chIdx++) {
            ChapterBoundary boundary = boundaries.get(chIdx);
            int start = boundary.startIndex;
            int end = (chIdx + 1 < boundaries.size()) ? boundaries.get(chIdx + 1).startIndex : spine.size();
            int chapterPageCount = Math.max(0, end - start);
            if (chapterPageCount == 0) continue;

            int effectiveOrder = chapterOrderOffset + chIdx;
            String chapterId = LocalModels.buildStableChapterId(bookId, effectiveOrder);
            String chEntry = (chapterEntryPath != null && !chapterEntryPath.isEmpty())
                    ? chapterEntryPath : "ch_" + effectiveOrder;
            LocalModels.Chapter chapter = new LocalModels.Chapter(
                    chapterId, bookId, effectiveOrder, boundary.title, chEntry, chapterPageCount);
            chapters.add(chapter);

            List<LocalModels.Page> pageList = new ArrayList<>();
            for (int pIdx = 0; pIdx < chapterPageCount; pIdx++) {
                if (callback != null && callback.isCancelled()) {
                    throw new java.io.InterruptedIOException("导入已取消");
                }
                int spineIdx = start + pIdx;
                SpineItem item = spine.get(spineIdx);
                String entryPath;
                String mime;

                if (item.isImageOrImageWrapper()) {
                    entryPath = item.resolvedImageEntry;
                    ZipEntry entry = zipFile.getEntry(entryPath);
                    if (entry == null) {
                        throw new IOException("EPUB 内页面图片缺失: " + entryPath);
                    }

                    long entrySize = entry.getSize();
                    if (entrySize > 0) totalBytes += entrySize;

                    if (probe != null) {
                        boolean readable = probe.isReadable(() -> zipFile.getInputStream(entry));
                        if (!readable) {
                            throw new IOException("EPUB 内图片损坏无法解码: " + entryPath);
                        }
                    }

                    mime = ArchiveIndex.detectMimeType(null, 0, entryPath);
                    if (firstValidPageEntry == null) {
                        firstValidPageEntry = entryPath;
                    }
                } else {
                    // Reflowable / Mixed text page (XHTML/HTML)
                    entryPath = item.fullZipPath;
                    ZipEntry entry = zipFile.getEntry(entryPath);
                    if (entry == null) {
                        throw new IOException("EPUB 内正文页面缺失: " + entryPath);
                    }
                    long entrySize = entry.getSize();
                    if (entrySize > 0) totalBytes += entrySize;
                    mime = (item.mediaType != null && !item.mediaType.isEmpty()) ? item.mediaType : "application/xhtml+xml";
                }

                String pageId = LocalModels.buildStablePageId(chapterId, pIdx);
                LocalModels.Page page = new LocalModels.Page(
                        pageId, bookId, chapterId, pIdx, entryPath, 0, 0, null, mime);
                pageList.add(page);
                totalPages++;
            }
            pagesByChapter.put(chapterId, pageList);
        }

        List<String> coverCandidates = new ArrayList<>();
        if (coverEntry != null && zipFile.getEntry(coverEntry) != null) {
            coverCandidates.add(coverEntry);
        }
        if (firstValidPageEntry != null && !coverCandidates.contains(firstValidPageEntry)) {
            coverCandidates.add(firstValidPageEntry);
        }
        if (coverCandidates.isEmpty()) {
            for (ManifestItem mi : manifest.values()) {
                if (mi.mediaType != null && mi.mediaType.startsWith("image/") && zipFile.getEntry(mi.href) != null) {
                    coverCandidates.add(mi.href);
                    break;
                }
            }
        }

        return new ArchiveIndex.ParseResult(
                chapters, pagesByChapter, totalPages, totalBytes, firstValidPageEntry, coverCandidates);
    }
}
