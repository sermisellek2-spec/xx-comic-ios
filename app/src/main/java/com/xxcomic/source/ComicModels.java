package com.xxcomic.source;

import java.util.ArrayList;
import java.util.List;

public final class ComicModels {
    private ComicModels() {
    }

    public static final class ComicSummary {
        public final String sourceId;
        public final String comicId;
        public final String title;
        public final String coverUrl;
        public final String subtitle;
        public final List<String> tags;

        public ComicSummary(String sourceId, String comicId, String title, String coverUrl, String subtitle, List<String> tags) {
            this.sourceId = sourceId;
            this.comicId = comicId;
            this.title = title;
            this.coverUrl = coverUrl;
            this.subtitle = subtitle;
            this.tags = tags == null ? new ArrayList<>() : tags;
        }
    }

    public static final class ComicDetail {
        public final ComicSummary summary;
        public final String author;
        public final String status;
        public final String description;
        public final String latestChapter;
        public final List<Chapter> chapters;

        public ComicDetail(ComicSummary summary, String author, String status, String description, String latestChapter, List<Chapter> chapters) {
            this.summary = summary;
            this.author = author;
            this.status = status;
            this.description = description;
            this.latestChapter = latestChapter;
            this.chapters = chapters == null ? new ArrayList<>() : chapters;
        }
    }

    public static final class Chapter {
        public final String chapterId;
        public final String title;
        public final String url;
        public final int sectionSlot;
        public final int chapterSlot;

        public Chapter(String chapterId, String title, String url, int sectionSlot, int chapterSlot) {
            this.chapterId = chapterId;
            this.title = title;
            this.url = url;
            this.sectionSlot = sectionSlot;
            this.chapterSlot = chapterSlot;
        }
    }

    public static final class ChapterPage {
        public final String chapterId;
        public final String title;
        public final List<String> imageUrls;
        public final String nextPageUrl;

        public ChapterPage(String chapterId, String title, List<String> imageUrls, String nextPageUrl) {
            this.chapterId = chapterId;
            this.title = title;
            this.imageUrls = imageUrls == null ? new ArrayList<>() : imageUrls;
            this.nextPageUrl = nextPageUrl;
        }
    }
}
