package com.xxcomic.local;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;
import com.xxcomic.source.ComicModels;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public class LocalDetailView {
    public interface Listener {
        void onBack();
        void onRead(LocalModels.Book book, ComicModels.ComicDetail detail, int chapterIndex);
        void onBookRenamed(LocalModels.Book updatedBook);
        void onBookDeleted(LocalModels.Book deletedBook);
    }

    public static View build(Activity activity, LocalModels.Book book,
                             ComicModels.ComicDetail detail,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             int savedChapterIndex,
                             Listener listener) {
        FrameLayout root = new FrameLayout(activity);
        root.setBackgroundColor(UIHelpers.CARD);

        ScrollView scroll = new ScrollView(activity);
        scroll.setVerticalScrollBarEnabled(false);
        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, new FrameLayout.LayoutParams(-1, -2));
        root.addView(scroll, new FrameLayout.LayoutParams(-1, -1));

        // 1. Hero Cover Header
        FrameLayout hero = new FrameLayout(activity);
        hero.setBackgroundColor(UIHelpers.SURFACE);
        int heroHeight = UIHelpers.dp(activity, 200);
        content.addView(hero, new LinearLayout.LayoutParams(-1, heroHeight));

        ImageView coverImage = new ImageView(activity);
        coverImage.setScaleType(ImageView.ScaleType.CENTER_CROP);
        coverImage.setImageResource(R.drawable.rem_no_image);
        if (!TextUtils.isEmpty(book.coverPath) && new File(book.coverPath).exists()) {
            coverImage.setImageURI(android.net.Uri.fromFile(new File(book.coverPath)));
        }
        hero.addView(coverImage, new FrameLayout.LayoutParams(-1, -1));

        // Dim overlay on hero
        View dim = new View(activity);
        dim.setBackgroundColor(Color.argb(70, 0, 0, 0));
        hero.addView(dim, new FrameLayout.LayoutParams(-1, -1));

        // Top navigation bar on hero
        LinearLayout topBar = new LinearLayout(activity);
        topBar.setOrientation(LinearLayout.HORIZONTAL);
        topBar.setGravity(Gravity.CENTER_VERTICAL);
        topBar.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 12), 0);

        TextView backBtn = UIHelpers.text(activity, "‹ 返回", 16, Color.WHITE, Typeface.BOLD);
        backBtn.setPadding(UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 8));
        backBtn.setContentDescription("返回书架");
        backBtn.setOnClickListener(v -> {
            if (listener != null) listener.onBack();
        });
        topBar.addView(backBtn, UIHelpers.weight(1));

        TextView renameBtn = UIHelpers.text(activity, "重命名", 14, Color.WHITE, Typeface.NORMAL);
        renameBtn.setBackground(UIHelpers.round(Color.argb(120, 0, 0, 0), UIHelpers.dp(activity, 14), Color.TRANSPARENT));
        renameBtn.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 6));
        renameBtn.setOnClickListener(v -> showRenameDialog(activity, book, store, listener));
        topBar.addView(renameBtn);

        TextView deleteBtn = UIHelpers.text(activity, "删除", 14, Color.rgb(255, 120, 120), Typeface.NORMAL);
        deleteBtn.setBackground(UIHelpers.round(Color.argb(120, 0, 0, 0), UIHelpers.dp(activity, 14), Color.TRANSPARENT));
        deleteBtn.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 6));
        LinearLayout.LayoutParams delParams = new LinearLayout.LayoutParams(-2, -2);
        delParams.leftMargin = UIHelpers.dp(activity, 8);
        deleteBtn.setLayoutParams(delParams);
        deleteBtn.setOnClickListener(v -> showDeleteDialog(activity, book, store, storageManager, listener));
        topBar.addView(deleteBtn);

        hero.addView(topBar, new FrameLayout.LayoutParams(-1, -2));

        // 2. Info Body Card
        LinearLayout body = new LinearLayout(activity);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 80));
        body.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 12), Color.TRANSPARENT));
        LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(-1, -2);
        bodyParams.topMargin = -UIHelpers.dp(activity, 16);
        content.addView(body, bodyParams);

        // Title and format badge
        LinearLayout titleRow = new LinearLayout(activity);
        titleRow.setOrientation(LinearLayout.HORIZONTAL);
        titleRow.setGravity(Gravity.CENTER_VERTICAL);

        TextView titleView = UIHelpers.text(activity, book.getDisplayTitle(), 20, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setMaxLines(2);
        titleView.setEllipsize(TextUtils.TruncateAt.END);
        titleRow.addView(titleView, UIHelpers.weight(1));

        TextView formatBadge = UIHelpers.text(activity, book.format.toUpperCase(Locale.US), 11, UIHelpers.ACCENT, Typeface.BOLD);
        formatBadge.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 4), UIHelpers.BORDER));
        formatBadge.setPadding(UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 3), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 3));
        titleRow.addView(formatBadge);

        body.addView(titleRow);

        // Metadata
        String metaText = "本地导入 · " + formatBytes(book.totalSize) + " · 共 " + book.chapterCount + " 话 / " + book.pageCount + " 页";
        TextView metaView = UIHelpers.text(activity, metaText, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        body.addView(metaView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 8)));

        // File path info
        TextView fileInfo = UIHelpers.text(activity, "储存路径: " + book.relativePath, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        fileInfo.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        fileInfo.setSingleLine(true);
        body.addView(fileInfo, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 4)));

        // Continue Reading Button
        int targetChapter = Math.max(0, Math.min(savedChapterIndex, detail.chapters.size() - 1));
        String readActionText = savedChapterIndex > 0 ? "继续阅读 第 " + (savedChapterIndex + 1) + " 话" : "开始阅读";
        Button readBtn = UIHelpers.primaryButton(activity, readActionText);
        readBtn.setOnClickListener(v -> {
            if (listener != null) listener.onRead(book, detail, targetChapter);
        });
        body.addView(readBtn, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 14), -1, UIHelpers.dp(activity, 44)));

        // Divider
        body.addView(UIHelpers.divider(activity), UIHelpers.marginTop(-1, UIHelpers.dp(activity, 16)));

        // Chapter Directory Section
        LinearLayout dirHeader = new LinearLayout(activity);
        dirHeader.setOrientation(LinearLayout.HORIZONTAL);
        dirHeader.setGravity(Gravity.CENTER_VERTICAL);
        dirHeader.setMinimumHeight(UIHelpers.dp(activity, 44));

        TextView dirTitle = UIHelpers.text(activity, "章节目录 (" + detail.chapters.size() + ")", 16, UIHelpers.TEXT, Typeface.BOLD);
        dirHeader.addView(dirTitle, UIHelpers.weight(1));

        final boolean[] desc = new boolean[]{false};
        TextView sortBtn = UIHelpers.text(activity, "正序 ⇅", 12, UIHelpers.ACCENT, Typeface.NORMAL);
        sortBtn.setPadding(UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 8));
        dirHeader.addView(sortBtn);
        body.addView(dirHeader);

        LinearLayout chapterList = new LinearLayout(activity);
        chapterList.setOrientation(LinearLayout.VERTICAL);
        body.addView(chapterList);

        Runnable renderChapters = () -> {
            chapterList.removeAllViews();
            List<ComicModels.Chapter> displayChapters = new ArrayList<>(detail.chapters);
            if (desc[0]) Collections.reverse(displayChapters);

            for (int i = 0; i < displayChapters.size(); i++) {
                ComicModels.Chapter ch = displayChapters.get(i);
                int actualIndex = detail.chapters.indexOf(ch);
                boolean isCurrent = actualIndex == targetChapter;

                LinearLayout row = new LinearLayout(activity);
                row.setOrientation(LinearLayout.HORIZONTAL);
                row.setGravity(Gravity.CENTER_VERTICAL);
                row.setMinimumHeight(UIHelpers.dp(activity, 42));
                row.setPadding(UIHelpers.dp(activity, 8), 0, UIHelpers.dp(activity, 8), 0);
                if (isCurrent) {
                    row.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 6), Color.TRANSPARENT));
                }

                TextView chTitle = UIHelpers.text(activity, ch.title, 14,
                        isCurrent ? UIHelpers.ACCENT : UIHelpers.TEXT,
                        isCurrent ? Typeface.BOLD : Typeface.NORMAL);
                row.addView(chTitle, UIHelpers.weight(1));

                if (isCurrent) {
                    TextView tag = UIHelpers.text(activity, "上次读到", 11, UIHelpers.ACCENT, Typeface.NORMAL);
                    row.addView(tag);
                }

                row.setOnClickListener(v -> {
                    if (listener != null) listener.onRead(book, detail, actualIndex);
                });
                chapterList.addView(row);
                if (i < displayChapters.size() - 1) {
                    chapterList.addView(UIHelpers.divider(activity));
                }
            }
        };

        sortBtn.setOnClickListener(v -> {
            desc[0] = !desc[0];
            sortBtn.setText(desc[0] ? "倒序 ⇅" : "正序 ⇅");
            renderChapters.run();
        });

        renderChapters.run();

        return root;
    }

    public static void showRenameDialog(Activity activity, LocalModels.Book book,
                                         LocalLibraryStore store, Listener listener) {
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
        builder.setTitle("重命名漫画");

        final EditText input = new EditText(activity);
        input.setSingleLine(true);
        input.setText(book.getDisplayTitle());
        input.setSelection(input.getText().length());
        int pad = UIHelpers.dp(activity, 16);
        input.setPadding(pad, pad, pad, pad);
        builder.setView(input);

        builder.setPositiveButton("保存", (dialog, which) -> {
            String newTitle = input.getText().toString().trim();
            if (TextUtils.isEmpty(newTitle)) {
                Toast.makeText(activity, "漫画名称不能为空", Toast.LENGTH_SHORT).show();
                return;
            }
            store.renameBook(book.id, newTitle);
            LocalModels.Book updated = store.getBook(book.id);
            if (listener != null && updated != null) {
                listener.onBookRenamed(updated);
            }
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    public static void showDeleteDialog(Activity activity, LocalModels.Book book,
                                         LocalLibraryStore store, LocalStorageManager storageManager,
                                         Listener listener) {
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
        builder.setTitle("删除本地漫画？");
        builder.setMessage("将删除该漫画在 App 内的副本并释放 " + formatBytes(book.totalSize) + " 存储空间。\n\n"
                + "提示：您手机上的原始文件不会受到任何影响。阅读历史与进度已保留，日后重新导入可继续阅读。");

        builder.setPositiveButton("删除", (dialog, which) -> {
            // Mark deleting
            store.markDeleting(book.id);
            // Delete files
            try {
                File bookFile = storageManager.getBookImportFile(book.relativePath);
                storageManager.deleteRecursively(bookFile);
            } catch (Exception ignored) {}
            try {
                File cover = storageManager.getCoverFile(book.id);
                if (cover.exists()) cover.delete();
            } catch (Exception ignored) {}
            // Complete deletion in db
            store.completeDeletion(book.id);
            Toast.makeText(activity, "已删除本地漫画", Toast.LENGTH_SHORT).show();
            if (listener != null) {
                listener.onBookDeleted(book);
            }
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        char unit = "KMGTPE".charAt(exp - 1);
        return String.format(Locale.US, "%.1f %cB", bytes / Math.pow(1024, exp), unit);
    }
}
