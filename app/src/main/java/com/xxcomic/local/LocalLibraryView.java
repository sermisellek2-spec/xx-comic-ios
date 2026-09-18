package com.xxcomic.local;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public class LocalLibraryView {
    private static FrameLayout activeLocalDeleteCover;
    private static View activeLocalDeleteOverlay;

    public interface Listener {
        void onBookClick(LocalModels.Book book);
        default void onBookLongClick(LocalModels.Book book) {}
        default void onDeleteBookWithUndo(LocalModels.Book book) {}
        void onImportClick();
        void onResumeRead(LocalModels.Book book);
        default void onHistoryClick() {}
    }

    public static void dismissActiveDeleteOverlay() {
        if (activeLocalDeleteCover != null && activeLocalDeleteOverlay != null
                && activeLocalDeleteOverlay.getParent() == activeLocalDeleteCover) {
            activeLocalDeleteCover.removeView(activeLocalDeleteOverlay);
            activeLocalDeleteCover.setTag(null);
        }
        activeLocalDeleteCover = null;
        activeLocalDeleteOverlay = null;
    }

    public static View build(Activity activity,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             String continueBookId,
                             int continueChapterIndex,
                             Listener listener) {
        return build(activity, store, storageManager, continueBookId, continueChapterIndex, null, null, listener);
    }

    public static View build(Activity activity,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             String continueBookId,
                             int continueChapterIndex,
                             View activeImportBanner,
                             Listener listener) {
        return build(activity, store, storageManager, continueBookId, continueChapterIndex, activeImportBanner, null, listener);
    }

    public static View build(Activity activity,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             String continueBookId,
                             int continueChapterIndex,
                             View activeImportBanner,
                             Set<String> hiddenBookIds,
                             Listener listener) {
        return build(activity, store, storageManager, continueBookId, continueChapterIndex, activeImportBanner, hiddenBookIds, null, listener);
    }

    public static View build(Activity activity,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             String continueBookId,
                             int continueChapterIndex,
                             View activeImportBanner,
                             Set<String> hiddenBookIds,
                             java.util.Map<String, Long> lastViewedMap,
                             Listener listener) {
        dismissActiveDeleteOverlay();

        ScrollView scroll = new ScrollView(activity);
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroll.setSmoothScrollingEnabled(true);
        scroll.setFadingEdgeLength(0);

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, UIHelpers.matchWrap());

        if (activeImportBanner != null) {
            content.addView(activeImportBanner, UIHelpers.marginBottom(-1, UIHelpers.dp(activity, 12)));
        }

        List<LocalModels.Book> allBooks = store.listBooks();
        java.util.Map<String, Integer> volumeCounts = store.getReadyVolumeCounts();
        List<LocalModels.Book> books = new ArrayList<>();
        if (hiddenBookIds != null && !hiddenBookIds.isEmpty()) {
            for (LocalModels.Book b : allBooks) {
                if (!hiddenBookIds.contains(b.id)) {
                    books.add(b);
                }
            }
        } else {
            books.addAll(allBooks);
        }

        // Sort books by most recently used (Math.max(createdAt, lastViewedAt)) descending, matching "我的书架"
        java.util.Collections.sort(books, (left, right) -> {
            long leftReadTime = 0L;
            if (lastViewedMap != null) {
                if (left.progressKey != null && lastViewedMap.containsKey(left.progressKey)) {
                    leftReadTime = Math.max(leftReadTime, lastViewedMap.get(left.progressKey));
                }
                if (lastViewedMap.containsKey(left.id)) {
                    leftReadTime = Math.max(leftReadTime, lastViewedMap.get(left.id));
                }
            }
            long rightReadTime = 0L;
            if (lastViewedMap != null) {
                if (right.progressKey != null && lastViewedMap.containsKey(right.progressKey)) {
                    rightReadTime = Math.max(rightReadTime, lastViewedMap.get(right.progressKey));
                }
                if (lastViewedMap.containsKey(right.id)) {
                    rightReadTime = Math.max(rightReadTime, lastViewedMap.get(right.id));
                }
            }
            long leftTime = Math.max(left.createdAt, leftReadTime);
            long rightTime = Math.max(right.createdAt, rightReadTime);
            if (leftTime != rightTime) {
                return Long.compare(rightTime, leftTime);
            }
            return Long.compare(right.createdAt, left.createdAt);
        });

        // 1. Continue Reading Row if available (Matches online bookshelf "接着看")
        if (!TextUtils.isEmpty(continueBookId) && (hiddenBookIds == null || !hiddenBookIds.contains(continueBookId))) {
            LocalModels.Book continueBook = store.getBook(continueBookId);
            if (continueBook != null) {
                LinearLayout header = new LinearLayout(activity);
                header.setOrientation(LinearLayout.HORIZONTAL);
                header.setGravity(Gravity.CENTER_VERTICAL);
                header.setMinimumHeight(UIHelpers.dp(activity, 36));

                TextView headerTitle = UIHelpers.text(activity, "接着看", 16, UIHelpers.TEXT, Typeface.BOLD);
                headerTitle.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
                header.addView(headerTitle, UIHelpers.weight(1));

                TextView historyBtn = UIHelpers.text(activity, "阅读历史 ›", 12, UIHelpers.ACCENT, Typeface.NORMAL);
                historyBtn.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
                historyBtn.setPadding(UIHelpers.dp(activity, 8), 0, 0, 0);
                historyBtn.setContentDescription("打开阅读历史");
                historyBtn.setOnClickListener(v -> {
                    if (listener != null) listener.onHistoryClick();
                });
                header.addView(historyBtn, new LinearLayout.LayoutParams(-2, -1));

                content.addView(header);
                content.addView(buildContinueReadingRow(activity, continueBook, continueChapterIndex, listener));
            }
        }

        // 2. Empty state or Grid
        if (books.isEmpty()) {
            content.addView(buildEmptyState(activity, listener));
        } else {
            // Section Header: 全部漫画  + 导入漫画           最近使用排序
            LinearLayout header = new LinearLayout(activity);
            header.setOrientation(LinearLayout.HORIZONTAL);
            header.setGravity(Gravity.CENTER_VERTICAL);
            header.setMinimumHeight(UIHelpers.dp(activity, 36));

            LinearLayout leftHost = new LinearLayout(activity);
            leftHost.setOrientation(LinearLayout.HORIZONTAL);
            leftHost.setGravity(Gravity.CENTER_VERTICAL);

            TextView title = UIHelpers.text(activity, "全部漫画", 16, UIHelpers.TEXT, Typeface.BOLD);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            leftHost.addView(title);

            TextView importBtn = UIHelpers.text(activity, "+ 导入漫画", 12, UIHelpers.ACCENT, Typeface.BOLD);
            importBtn.setPadding(UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 4));
            importBtn.setOnClickListener(v -> {
                if (listener != null) listener.onImportClick();
            });
            LinearLayout.LayoutParams importParams = new LinearLayout.LayoutParams(-2, -2);
            importParams.leftMargin = UIHelpers.dp(activity, 10);
            leftHost.addView(importBtn, importParams);

            header.addView(leftHost, UIHelpers.weight(1));

            TextView sortView = UIHelpers.text(activity, "最近使用排序", 12, UIHelpers.TEXT3, Typeface.NORMAL);
            sortView.setGravity(Gravity.CENTER_VERTICAL | Gravity.RIGHT);
            sortView.setPadding(UIHelpers.dp(activity, 8), 0, 0, 0);
            header.addView(sortView, new LinearLayout.LayoutParams(-2, -1));

            content.addView(header);

            // 3-column Grid
            int colCount = 3;
            for (int i = 0; i < books.size(); i += colCount) {
                LinearLayout row = new LinearLayout(activity);
                row.setOrientation(LinearLayout.HORIZONTAL);
                for (int col = 0; col < colCount; col++) {
                    int index = i + col;
                    if (index < books.size()) {
                        LocalModels.Book book = books.get(index);
                        Integer count = volumeCounts.get(book.id);
                        row.addView(buildBookCard(activity, book, count == null ? 0 : count, listener), UIHelpers.weight(1));
                    } else {
                        row.addView(new View(activity), UIHelpers.weight(1));
                    }
                    if (col < colCount - 1) {
                        row.addView(UIHelpers.space(activity, UIHelpers.dp(activity, 5), 1));
                    }
                }
                content.addView(row, UIHelpers.marginBottom(-1, UIHelpers.dp(activity, 10)));
            }
        }

        return scroll;
    }

    private static View buildContinueReadingRow(Activity activity, LocalModels.Book book,
                                                int chapterIndex, Listener listener) {
        LinearLayout strip = new LinearLayout(activity);
        strip.setOrientation(LinearLayout.VERTICAL);
        strip.addView(UIHelpers.divider(activity));

        LinearLayout row = new LinearLayout(activity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(activity, 1), 0, UIHelpers.dp(activity, 1), 0);

        // Circular Cover
        ImageView cover = new ImageView(activity);
        cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
        cover.setImageResource(R.drawable.rem_no_image);
        LocalLibrary.loadCover(activity, cover, book);
        cover.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 17), Color.TRANSPARENT));
        cover.setClipToOutline(true);
        cover.setContentDescription(book.getDisplayTitle() + "封面");
        row.addView(cover, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 34), UIHelpers.dp(activity, 34)));

        // Title and chapter info
        LinearLayout copy = new LinearLayout(activity);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(activity, 10), 0, 0, 0);

        TextView title = UIHelpers.text(activity, book.getDisplayTitle(), 15, UIHelpers.TEXT, Typeface.BOLD);
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        copy.addView(title);

        String readDesc = "上次看到 · 第 " + (chapterIndex + 1) + " 话";
        TextView sub = UIHelpers.text(activity, readDesc, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        copy.addView(sub, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 2)));

        row.addView(copy, UIHelpers.weight(1));

        TextView resume = UIHelpers.text(activity, "续读 ›", 12, UIHelpers.ACCENT, Typeface.BOLD);
        resume.setGravity(Gravity.CENTER);
        resume.setPadding(UIHelpers.dp(activity, 8), 0, UIHelpers.dp(activity, 2), 0);
        resume.setContentDescription("继续阅读");
        resume.setOnClickListener(v -> {
            if (listener != null) listener.onResumeRead(book);
        });
        row.addView(resume, new LinearLayout.LayoutParams(-2, -1));

        row.setOnClickListener(v -> {
            if (listener != null) listener.onResumeRead(book);
        });

        strip.addView(row, new LinearLayout.LayoutParams(-1, UIHelpers.dp(activity, 50)));
        strip.addView(UIHelpers.divider(activity));
        return strip;
    }

    private static View buildBookCard(Activity activity, LocalModels.Book book, int volumeCount, Listener listener) {
        LinearLayout card = new LinearLayout(activity);
        card.setOrientation(LinearLayout.VERTICAL);

        int screenWidth = activity.getResources().getDisplayMetrics().widthPixels;
        float density = activity.getResources().getDisplayMetrics().density;
        int coverHeight = Math.min(154, Math.round((screenWidth / density - 42f) / 3f * 4f / 3f));

        FrameLayout coverWrap = new FrameLayout(activity);
        coverWrap.setBackground(UIHelpers.round(UIHelpers.PLACEHOLDER, UIHelpers.dp(activity, 4), Color.TRANSPARENT));
        coverWrap.setClipToOutline(true);

        ImageView cover = new ImageView(activity);
        cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
        cover.setImageResource(R.drawable.rem_no_image);
        LocalLibrary.loadCover(activity, cover, book);
        coverWrap.addView(cover, new FrameLayout.LayoutParams(-1, -1));

        // Small format badge at top right
        TextView badge = UIHelpers.text(activity, LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) ? "离线" : book.format.toUpperCase(Locale.US), 9, Color.WHITE, Typeface.BOLD);
        badge.setBackground(UIHelpers.round(Color.argb(160, 20, 40, 58), UIHelpers.dp(activity, 3), Color.TRANSPARENT));
        badge.setPadding(UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 1), UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 1));
        FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(-2, -2);
        badgeParams.gravity = Gravity.TOP | Gravity.RIGHT;
        badgeParams.setMargins(0, UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 4), 0);
        coverWrap.addView(badge, badgeParams);

        card.addView(coverWrap, new LinearLayout.LayoutParams(-1, UIHelpers.dp(activity, coverHeight)));

        // Title
        TextView title = UIHelpers.text(activity, book.getDisplayTitle(), 13, UIHelpers.TEXT, Typeface.BOLD);
        title.setMaxLines(2);
        title.setEllipsize(TextUtils.TruncateAt.END);
        title.setMinHeight(UIHelpers.dp(activity, 34));
        card.addView(title, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 4)));
        if (volumeCount > 1)
            card.addView(UIHelpers.text(activity, volumeCount + " 卷 · 可阅读", 10, UIHelpers.TEXT3, Typeface.NORMAL));

        card.setOnClickListener(v -> {
            if (activeLocalDeleteOverlay != null) {
                dismissActiveDeleteOverlay();
                return;
            }
            if (listener != null) listener.onBookClick(book);
        });

        card.setOnLongClickListener(v -> {
            showLocalDeleteOverlay(activity, coverWrap, book, listener);
            if (listener != null) listener.onBookLongClick(book);
            return true;
        });

        return card;
    }

    private static void showLocalDeleteOverlay(Activity activity, FrameLayout coverWrap,
                                               LocalModels.Book book, Listener listener) {
        Object tag = coverWrap.getTag();
        if (tag instanceof View) {
            coverWrap.removeView((View) tag);
            coverWrap.setTag(null);
            activeLocalDeleteCover = null;
            activeLocalDeleteOverlay = null;
            return;
        }
        dismissActiveDeleteOverlay();

        FrameLayout overlay = new FrameLayout(activity);
        overlay.setBackgroundColor(Color.argb(165, 20, 43, 62));
        ImageView trash = UIHelpers.vectorIconButton(activity, R.drawable.ic_trash, Color.WHITE, 13);
        trash.setBackground(UIHelpers.round(UIHelpers.DANGER, UIHelpers.dp(activity, 24), Color.TRANSPARENT));
        trash.setContentDescription("删除漫画");
        trash.setOnClickListener(v -> {
            coverWrap.removeView(overlay);
            coverWrap.setTag(null);
            activeLocalDeleteCover = null;
            activeLocalDeleteOverlay = null;
            if (listener != null) {
                listener.onDeleteBookWithUndo(book);
            }
        });
        overlay.addView(trash, UIHelpers.frame(UIHelpers.dp(activity, 48), UIHelpers.dp(activity, 48), Gravity.CENTER, 0, 0, 0, 0));
        overlay.setOnClickListener(v -> {
            coverWrap.removeView(overlay);
            coverWrap.setTag(null);
            activeLocalDeleteCover = null;
            activeLocalDeleteOverlay = null;
        });
        coverWrap.addView(overlay, UIHelpers.match());
        coverWrap.setTag(overlay);
        activeLocalDeleteCover = coverWrap;
        activeLocalDeleteOverlay = overlay;
    }

    private static View buildEmptyState(Activity activity, Listener listener) {
        LinearLayout state = new LinearLayout(activity);
        state.setOrientation(LinearLayout.VERTICAL);
        state.setGravity(Gravity.CENTER);
        state.setMinimumHeight(UIHelpers.dp(activity, 320));

        ImageView art = new ImageView(activity);
        art.setImageResource(R.drawable.rem_empty);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        art.setContentDescription("蕾姆提示本地书架为空");
        int artSize = UIHelpers.dp(activity, 80);
        state.addView(art, new LinearLayout.LayoutParams(artSize, artSize));

        TextView title = UIHelpers.text(activity, "本地书架还是空的", 17, UIHelpers.TEXT, Typeface.BOLD);
        state.addView(title, UIHelpers.marginTop(-2, UIHelpers.dp(activity, 10)));

        TextView desc = UIHelpers.text(activity, "支持导入本地 ZIP/CBZ 压缩包、EPUB 电子书与 PDF 文档\n文件将安全保存在本机，不修改用户原文件", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        desc.setGravity(Gravity.CENTER);
        state.addView(desc, UIHelpers.marginTop(-2, UIHelpers.dp(activity, 6)));

        Button importBtn = UIHelpers.primaryButton(activity, "+ 导入本地漫画");
        importBtn.setOnClickListener(v -> {
            if (listener != null) listener.onImportClick();
        });
        state.addView(importBtn, UIHelpers.marginTop(UIHelpers.dp(activity, 120), UIHelpers.dp(activity, 14), -2, UIHelpers.dp(activity, 40)));

        return state;
    }

    private static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        char unit = "KMGTPE".charAt(exp - 1);
        return String.format(Locale.US, "%.1f %cB", bytes / Math.pow(1024, exp), unit);
    }
}
