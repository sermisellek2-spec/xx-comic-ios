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
import java.util.List;
import java.util.Locale;

public class LocalLibraryView {
    public interface Listener {
        void onBookClick(LocalModels.Book book);
        void onBookLongClick(LocalModels.Book book);
        void onImportClick();
        void onResumeRead(LocalModels.Book book);
    }

    public static View build(Activity activity,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             String continueBookId,
                             int continueChapterIndex,
                             Listener listener) {
        ScrollView scroll = new ScrollView(activity);
        scroll.setVerticalScrollBarEnabled(false);

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, UIHelpers.dp(activity, 20));
        scroll.addView(content, new FrameLayout.LayoutParams(-1, -2));

        List<LocalModels.Book> books = store.listBooks();

        // 1. Continue Reading Row if available
        if (!TextUtils.isEmpty(continueBookId)) {
            LocalModels.Book continueBook = store.getBook(continueBookId);
            if (continueBook != null) {
                content.addView(buildContinueReadingRow(activity, continueBook, continueChapterIndex, listener));
            }
        }

        // 2. Empty state or Grid
        if (books.isEmpty()) {
            content.addView(buildEmptyState(activity, listener));
        } else {
            // Section Header
            LinearLayout header = new LinearLayout(activity);
            header.setOrientation(LinearLayout.HORIZONTAL);
            header.setGravity(Gravity.CENTER_VERTICAL);
            header.setMinimumHeight(UIHelpers.dp(activity, 36));

            TextView title = UIHelpers.text(activity, "全部本地漫画 (" + books.size() + ")", 15, UIHelpers.TEXT, Typeface.BOLD);
            header.addView(title, UIHelpers.weight(1));

            TextView importBtn = UIHelpers.text(activity, "+ 导入漫画", 12, UIHelpers.ACCENT, Typeface.BOLD);
            importBtn.setPadding(UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 6));
            importBtn.setOnClickListener(v -> {
                if (listener != null) listener.onImportClick();
            });
            header.addView(importBtn);

            content.addView(header, UIHelpers.marginBottom(-1, UIHelpers.dp(activity, 8)));

            // 3-column Grid
            int colCount = 3;
            for (int i = 0; i < books.size(); i += colCount) {
                LinearLayout row = new LinearLayout(activity);
                row.setOrientation(LinearLayout.HORIZONTAL);
                for (int col = 0; col < colCount; col++) {
                    int index = i + col;
                    if (index < books.size()) {
                        row.addView(buildBookCard(activity, books.get(index), listener), UIHelpers.weight(1));
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

        LinearLayout row = new LinearLayout(activity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(activity, 2), UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 2), UIHelpers.dp(activity, 8));

        // Cover
        ImageView cover = new ImageView(activity);
        cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
        cover.setImageResource(R.drawable.rem_no_image);
        if (!TextUtils.isEmpty(book.coverPath) && new File(book.coverPath).exists()) {
            cover.setImageURI(android.net.Uri.fromFile(new File(book.coverPath)));
        }
        cover.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 6), Color.TRANSPARENT));
        cover.setClipToOutline(true);
        row.addView(cover, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 36), UIHelpers.dp(activity, 48)));

        // Title and chapter info
        LinearLayout info = new LinearLayout(activity);
        info.setOrientation(LinearLayout.VERTICAL);
        info.setPadding(UIHelpers.dp(activity, 10), 0, 0, 0);

        TextView title = UIHelpers.text(activity, book.getDisplayTitle(), 14, UIHelpers.TEXT, Typeface.BOLD);
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        info.addView(title);

        String readDesc = "上次看到 · 第 " + (chapterIndex + 1) + " 话";
        TextView sub = UIHelpers.text(activity, readDesc, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        info.addView(sub, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 2)));

        row.addView(info, UIHelpers.weight(1));

        TextView resume = UIHelpers.text(activity, "续读 ›", 12, UIHelpers.ACCENT, Typeface.BOLD);
        resume.setGravity(Gravity.CENTER);
        resume.setPadding(UIHelpers.dp(activity, 8), 0, UIHelpers.dp(activity, 2), 0);
        resume.setOnClickListener(v -> {
            if (listener != null) listener.onResumeRead(book);
        });
        row.addView(resume);

        row.setOnClickListener(v -> {
            if (listener != null) listener.onResumeRead(book);
        });

        strip.addView(row);
        strip.addView(UIHelpers.divider(activity));
        return strip;
    }

    private static View buildBookCard(Activity activity, LocalModels.Book book, Listener listener) {
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
        if (!TextUtils.isEmpty(book.coverPath) && new File(book.coverPath).exists()) {
            cover.setImageURI(android.net.Uri.fromFile(new File(book.coverPath)));
        }
        coverWrap.addView(cover, new FrameLayout.LayoutParams(-1, -1));

        // Small format badge at top right
        TextView badge = UIHelpers.text(activity, book.format.toUpperCase(Locale.US), 9, Color.WHITE, Typeface.BOLD);
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

        // Info (chapters / pages / size)
        String info = book.chapterCount + " 话 · " + formatBytes(book.totalSize);
        TextView sub = UIHelpers.text(activity, info, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        sub.setSingleLine(true);
        card.addView(sub, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 2)));

        card.setOnClickListener(v -> {
            if (listener != null) listener.onBookClick(book);
        });

        card.setOnLongClickListener(v -> {
            if (listener != null) listener.onBookLongClick(book);
            return true;
        });

        return card;
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

        TextView desc = UIHelpers.text(activity, "支持导入本地 ZIP/CBZ 压缩包和图片文件夹\n文件将安全保存在本机，不修改用户原文件", 12, UIHelpers.TEXT3, Typeface.NORMAL);
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
