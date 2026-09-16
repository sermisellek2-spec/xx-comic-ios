package com.xxcomic.favorite;

import com.xxcomic.source.ComicModels;
import com.xxcomic.source.ComicSource;

import java.util.List;

public final class FavoriteUpdateChecker {
    private FavoriteUpdateChecker() {
    }

    public static FavoriteRevision check(ComicSource client, String comicId, FavoriteRevision baseline) {
        if (client == null || isEmpty(comicId)) {
            return null;
        }
        try {
            ComicModels.ComicDetail detail = client.detail(comicId);
            if (detail == null) {
                return null;
            }
            // If detail already contains full chapters, use them
            if (detail.chapters != null && !detail.chapters.isEmpty()) {
                return FavoriteRevision.fromChapters(detail.latestChapter, detail.chapters);
            }

            // If baseline relied on CHAPTER_SET or detail has no reliable chapter evidence,
            // call chapters() to obtain reliable chapter IDs
            boolean needChapters = baseline != null && FavoriteRevision.MODE_CHAPTER_SET.equals(baseline.mode);
            if (needChapters || isEmpty(detail.latestChapter)) {
                try {
                    List<ComicModels.Chapter> chapters = client.chapters(comicId);
                    if (chapters != null && !chapters.isEmpty()) {
                        return FavoriteRevision.fromChapters(detail.latestChapter, chapters);
                    }
                } catch (Exception ignored) {
                    // chapters() failed, fall back to detail if it has comparable info
                }
            }

            // Fall back to detail snapshot
            if (!isEmpty(detail.latestChapter)) {
                return FavoriteRevision.fromDetail(detail);
            }
            return null;
        } catch (Exception error) {
            // All errors (network, timeout, Cloudflare verification, retired source) are captured silently
            return null;
        }
    }

    private static boolean isEmpty(String str) {
        return str == null || str.isEmpty();
    }
}
