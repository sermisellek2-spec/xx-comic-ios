package com.xxcomic.local;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
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
    private static final int CHAPTER_DRAWER_BATCH_SIZE = 40;

    public interface Listener {
        void onBack();
        void onRead(LocalModels.Book book, ComicModels.ComicDetail detail, int chapterIndex);
        void onBookRenamed(LocalModels.Book updatedBook);
        void onBookDeleted(LocalModels.Book deletedBook);
        default void onAddVolumes(LocalModels.Book book) {}
        default void showToast(String message) {}
    }

    public static View build(Activity activity, LocalModels.Book book,
                             ComicModels.ComicDetail detail,
                             LocalLibraryStore store,
                             LocalStorageManager storageManager,
                             int savedChapterIndex,
                             boolean hasRead,
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
        LocalLibrary.loadCover(activity, coverImage, book);
        hero.addView(coverImage, new FrameLayout.LayoutParams(-1, -1));

        // Dim overlay on hero
        View dim = new View(activity);
        dim.setBackgroundColor(Color.argb(70, 0, 0, 0));
        hero.addView(dim, new FrameLayout.LayoutParams(-1, -1));

        // 2. Info Body Card
        LinearLayout body = new LinearLayout(activity);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 82));
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

        TextView formatBadge = UIHelpers.text(activity, LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) ? "离线" : book.format.toUpperCase(Locale.US), 11, UIHelpers.ACCENT, Typeface.BOLD);
        formatBadge.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 4), UIHelpers.BORDER));
        formatBadge.setPadding(UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 3), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 3));
        titleRow.addView(formatBadge);

        body.addView(titleRow);

        // Metadata: only type + file size
        String typeLabel = LocalModels.isDownload(book) ? "离线下载" : "本地导入";
        String metaText = typeLabel + " · " + formatBytes(book.totalSize);
        List<LocalModels.Volume> volumes = store.getVolumes(book.id);
        if (volumes.size() > 1) metaText += " · " + volumes.size() + " 卷";
        TextView metaView = UIHelpers.text(activity, metaText, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        body.addView(metaView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 8)));

        // Divider
        body.addView(UIHelpers.divider(activity), UIHelpers.marginTop(-1, UIHelpers.dp(activity, 12)));

        // 3. Chapter Entry (Opens 76% Drawer)
        final int targetChapter = Math.max(0, Math.min(savedChapterIndex, detail.chapters.size() - 1));
        View chapterEntryView = buildChapterEntry(activity, root, book, detail, targetChapter, hasRead, (selectedChapter) -> {
            if (listener != null) listener.onRead(book, detail, selectedChapter);
        });
        body.addView(chapterEntryView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 12)));
        if (LocalModels.SOURCE_TYPE_IMPORT.equals(book.sourceType)) {
            TextView add = UIHelpers.text(activity, "+ 添加分卷", 13, UIHelpers.ACCENT, Typeface.NORMAL);
            add.setPadding(0, UIHelpers.dp(activity, 14), 0, UIHelpers.dp(activity, 14));
            add.setOnClickListener(v -> { if (listener != null) listener.onAddVolumes(book); });
            body.addView(add);
        }
        if (volumes.size() > 1) {
            TextView manage = UIHelpers.text(activity, "管理分卷  ›", 13, UIHelpers.ACCENT, Typeface.NORMAL);
            manage.setPadding(0, UIHelpers.dp(activity, 14), 0, UIHelpers.dp(activity, 14));
            manage.setOnClickListener(v -> showVolumeManager(activity, book, store, storageManager, listener));
            body.addView(manage);
        }

        // 4. Fixed Bottom Action Bar (Matches online detail style & typography)
        LinearLayout actions = new LinearLayout(activity);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 10));
        actions.setBackgroundColor(UIHelpers.CARD);

        // Reading Action Button full width (two-line typography matching 图4)
        LinearLayout readBtn = new LinearLayout(activity);
        readBtn.setOrientation(LinearLayout.VERTICAL);
        readBtn.setGravity(Gravity.CENTER);
        readBtn.setPadding(UIHelpers.dp(activity, 12), 0, UIHelpers.dp(activity, 12), 0);
        readBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(activity, 7), Color.TRANSPARENT));

        String title = hasRead ? "继续阅读" : "开始阅读";
        String subtitle = hasRead ? "第 " + (targetChapter + 1) + " 话" : "从第 1 话开始";

        TextView titleActionView = UIHelpers.text(activity, title, 13, UIHelpers.ON_ACCENT, Typeface.BOLD);
        titleActionView.setGravity(Gravity.CENTER);
        titleActionView.setIncludeFontPadding(false);
        titleActionView.setSingleLine(true);
        titleActionView.setEllipsize(TextUtils.TruncateAt.END);
        readBtn.addView(titleActionView);

        TextView subtitleActionView = UIHelpers.text(activity, subtitle, 10, UIHelpers.ON_ACCENT, Typeface.NORMAL);
        subtitleActionView.setGravity(Gravity.CENTER);
        subtitleActionView.setIncludeFontPadding(false);
        subtitleActionView.setAlpha(.84f);
        subtitleActionView.setSingleLine(true);
        subtitleActionView.setEllipsize(TextUtils.TruncateAt.END);
        readBtn.addView(subtitleActionView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 2)));

        readBtn.setContentDescription(title + "，" + subtitle);
        readBtn.setOnClickListener(v -> {
            if (listener != null) listener.onRead(book, detail, targetChapter);
        });
        actions.addView(readBtn, new LinearLayout.LayoutParams(-1, UIHelpers.dp(activity, 44)));

        root.addView(actions, UIHelpers.frame(-1, UIHelpers.dp(activity, 62), Gravity.BOTTOM, 0, 0, 0, 0));

        return root;
    }

    public static void showMoreActionSheet(Activity activity, LocalModels.Book book,
                                           LocalLibraryStore store, LocalStorageManager storageManager,
                                           Listener listener) {
        if (activity == null || activity.isFinishing()) return;

        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout sheet = new LinearLayout(activity);
        sheet.setOrientation(LinearLayout.VERTICAL);
        sheet.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 20));

        GradientDrawable bg = new GradientDrawable();
        bg.setColor(UIHelpers.CARD);
        float r = UIHelpers.dp(activity, 16);
        bg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        sheet.setBackground(bg);

        // Top drag handle
        FrameLayout handleHost = new FrameLayout(activity);
        View handle = new View(activity);
        handle.setBackground(UIHelpers.round(UIHelpers.BORDER, UIHelpers.dp(activity, 2), Color.TRANSPARENT));
        handleHost.addView(handle, new FrameLayout.LayoutParams(UIHelpers.dp(activity, 36), UIHelpers.dp(activity, 4), Gravity.CENTER));
        sheet.addView(handleHost, new LinearLayout.LayoutParams(-1, UIHelpers.dp(activity, 18)));

        // Comic title
        TextView sheetTitle = UIHelpers.text(activity, book.getDisplayTitle(), 13, UIHelpers.TEXT3, Typeface.NORMAL);
        sheetTitle.setSingleLine(true);
        sheetTitle.setEllipsize(TextUtils.TruncateAt.END);
        sheetTitle.setGravity(Gravity.CENTER);
        sheetTitle.setPadding(0, UIHelpers.dp(activity, 2), 0, UIHelpers.dp(activity, 12));
        sheet.addView(sheetTitle);

        sheet.addView(UIHelpers.divider(activity));

        // Action 1: 重命名
        TextView renameBtn = UIHelpers.text(activity, "重命名", 15, UIHelpers.TEXT, Typeface.NORMAL);
        renameBtn.setGravity(Gravity.CENTER);
        renameBtn.setPadding(0, UIHelpers.dp(activity, 14), 0, UIHelpers.dp(activity, 14));
        renameBtn.setOnClickListener(v -> {
            dialog.dismiss();
            showRenameDialog(activity, book, store, listener);
        });
        sheet.addView(renameBtn, new LinearLayout.LayoutParams(-1, -2));

        sheet.addView(UIHelpers.divider(activity));

        // Action 2: 删除漫画
        TextView deleteBtn = UIHelpers.text(activity, "删除漫画", 15, UIHelpers.DANGER, Typeface.NORMAL);
        deleteBtn.setGravity(Gravity.CENTER);
        deleteBtn.setPadding(0, UIHelpers.dp(activity, 14), 0, UIHelpers.dp(activity, 14));
        deleteBtn.setOnClickListener(v -> {
            dialog.dismiss();
            showDeleteDialog(activity, book, store, storageManager, listener);
        });
        sheet.addView(deleteBtn, new LinearLayout.LayoutParams(-1, -2));

        sheet.addView(UIHelpers.divider(activity));

        // Action 3: 取消
        TextView cancelBtn = UIHelpers.text(activity, "取消", 15, UIHelpers.TEXT3, Typeface.NORMAL);
        cancelBtn.setGravity(Gravity.CENTER);
        cancelBtn.setPadding(0, UIHelpers.dp(activity, 14), 0, UIHelpers.dp(activity, 14));
        cancelBtn.setOnClickListener(v -> dialog.dismiss());
        sheet.addView(cancelBtn, new LinearLayout.LayoutParams(-1, -2));

        dialog.setContentView(sheet);

        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            window.setGravity(Gravity.BOTTOM);
            window.setWindowAnimations(android.R.style.Animation_InputMethod);
            window.setDimAmount(0.45f);
        }

        dialog.show();
    }

    private static final java.util.concurrent.ExecutorService volumeIo = java.util.concurrent.Executors.newSingleThreadExecutor();

    private static void showVolumeManager(Activity activity, LocalModels.Book book, LocalLibraryStore store,
                                           LocalStorageManager storage, Listener listener) {
        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 20));
        panel.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 16), Color.TRANSPARENT));
        panel.addView(UIHelpers.text(activity, "管理分卷", 17, UIHelpers.TEXT, Typeface.BOLD));
        panel.addView(UIHelpers.text(activity, "调整顺序不改变卷内章节；移除只清理 App 副本，原文件保留。", 12, UIHelpers.TEXT3, Typeface.NORMAL));
        ScrollView scroll = new ScrollView(activity);
        LinearLayout rows = new LinearLayout(activity);
        rows.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(rows);
        for (LocalModels.Volume volume : store.getVolumes(book.id)) {
            LinearLayout row = new LinearLayout(activity);
            row.setGravity(Gravity.CENTER_VERTICAL);
            TextView title = UIHelpers.text(activity, volume.title, 13, UIHelpers.TEXT, Typeface.NORMAL);
            title.setMaxLines(2);
            row.addView(title, UIHelpers.weight(1));
            for (int direction : new int[]{-1, 1, 0}) {
                TextView action = UIHelpers.text(activity, direction == 0 ? "移除" : direction < 0 ? "↑" : "↓", 14,
                        direction == 0 ? UIHelpers.DANGER : UIHelpers.ACCENT, Typeface.NORMAL);
                action.setGravity(Gravity.CENTER);
                action.setContentDescription((direction == 0 ? "移除 " : direction < 0 ? "上移 " : "下移 ") + volume.title);
                row.addView(action, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 46), UIHelpers.dp(activity, 48)));
                action.setOnClickListener(v -> {
                    Runnable change = () -> {
                        dialog.dismiss();
                        volumeIo.execute(() -> {
                            boolean ok = true;
                            try {
                                if (direction == 0) ok = store.deleteVolume(book.id, volume.id, storage);
                                else store.moveVolume(book.id, volume.id, direction);
                            } catch (Exception e) { ok = false; }
                            boolean done = ok;
                            activity.runOnUiThread(() -> {
                                if (activity.isDestroyed() || activity.isFinishing()) return;
                                if (!done) { Toast.makeText(activity, "操作未完成，请重试", Toast.LENGTH_SHORT).show(); return; }
                                LocalModels.Book latest = store.getBook(book.id);
                                if (listener != null) {
                                    if (latest == null) listener.onBookDeleted(book);
                                    else listener.onBookRenamed(latest);
                                }
                            });
                        });
                    };
                    if (direction != 0) change.run();
                    else {
                        LinearLayout message = new LinearLayout(activity);
                        message.setOrientation(LinearLayout.VERTICAL);
                        message.setPadding(UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 20), 0);
                        message.addView(UIHelpers.text(activity, "移除这一卷？", 17, UIHelpers.TEXT, Typeface.BOLD));
                        message.addView(UIHelpers.text(activity, volume.title + "\n其他分卷和手机中的原文件不受影响。",
                                13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(activity, 8)));
                        AlertDialog confirm = new AlertDialog.Builder(activity).setView(message)
                                .setNegativeButton("取消", null).setPositiveButton("移除", (d, which) -> change.run()).create();
                        confirm.show();
                        if (confirm.getWindow() != null)
                            confirm.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 12), Color.TRANSPARENT));
                        confirm.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(UIHelpers.TEXT3);
                        confirm.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(UIHelpers.DANGER);
                    }
                });
            }
            rows.addView(row);
        }
        panel.addView(scroll, new LinearLayout.LayoutParams(-1,
                Math.min(UIHelpers.dp(activity, 420), activity.getResources().getDisplayMetrics().heightPixels / 2)));
        dialog.setContentView(panel);
        dialog.show();
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.setLayout(-1, -2); window.setGravity(Gravity.BOTTOM);
            window.setWindowAnimations(android.R.style.Animation_InputMethod);
        }
    }

    private interface OnChapterSelected {
        void onSelect(int chapterIndex);
    }

    private static View buildChapterEntry(Activity activity, View rootLocation, LocalModels.Book book, ComicModels.ComicDetail detail,
                                          int targetChapter, boolean hasRead, OnChapterSelected onSelect) {
        LinearLayout row = new LinearLayout(activity);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 9), UIHelpers.dp(activity, 10), UIHelpers.dp(activity, 9));
        row.setMinimumHeight(UIHelpers.dp(activity, 54));
        row.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 7), UIHelpers.BORDER));
        row.setOnClickListener(v -> showChapterDrawer(activity, rootLocation, book, detail, targetChapter, hasRead, onSelect));

        LinearLayout text = new LinearLayout(activity);
        text.setOrientation(LinearLayout.VERTICAL);
        text.addView(UIHelpers.text(activity, "章节目录", 14, UIHelpers.TEXT, Typeface.BOLD));
        String sourceTag = LocalModels.isDownload(book) ? "离线下载"
                : (LocalModels.FORMAT_PDF.equals(book.format) ? "PDF 文档"
                : (LocalModels.FORMAT_EPUB.equals(book.format) ? "EPUB 电子书"
                : (LocalModels.FORMAT_AZW3.equals(book.format) ? "AZW3 电子书"
                : (LocalModels.FORMAT_AZW.equals(book.format) ? "AZW 电子书"
                : (LocalModels.FORMAT_MOBI.equals(book.format) ? "MOBI 电子书" : "本地漫画")))));
        String status = detail.chapters.isEmpty() ? "暂无章节" : detail.chapters.size() + " 话 · " + sourceTag;
        text.addView(UIHelpers.text(activity, status, 11, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, UIHelpers.dp(activity, 3)));
        row.addView(text, UIHelpers.weight(1));

        ImageView action = UIHelpers.vectorIconButton(activity, R.drawable.ic_chevron_right, UIHelpers.TEXT3, 3);
        row.addView(action, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 24), UIHelpers.dp(activity, 24)));
        return row;
    }

    private static void showChapterDrawer(Activity activity, View rootLocation, LocalModels.Book book, ComicModels.ComicDetail detail,
                                          int targetChapter, boolean hasRead, OnChapterSelected onSelect) {
        if (activity == null || activity.isFinishing()) return;

        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 10));
        panel.setBackgroundColor(UIHelpers.CARD);

        // Header
        LinearLayout header = new LinearLayout(activity);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setMinimumHeight(UIHelpers.dp(activity, 43));
        panel.addView(header, new LinearLayout.LayoutParams(-1, UIHelpers.dp(activity, 43)));

        LinearLayout titleHost = new LinearLayout(activity);
        titleHost.setOrientation(LinearLayout.VERTICAL);
        titleHost.addView(UIHelpers.text(activity, "章节目录", 16, UIHelpers.TEXT, Typeface.BOLD));
        titleHost.addView(UIHelpers.text(activity, "共 " + detail.chapters.size() + " 话", 11, UIHelpers.TEXT3, Typeface.NORMAL),
                UIHelpers.marginTop(-1, UIHelpers.dp(activity, 2)));
        header.addView(titleHost, UIHelpers.weight(1));

        ImageView close = UIHelpers.vectorIconButton(activity, R.drawable.ic_close, UIHelpers.TEXT2, 6);
        close.setContentDescription("关闭目录");
        header.addView(close, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 34), UIHelpers.dp(activity, 34)));

        panel.addView(UIHelpers.divider(activity));

        // Tools (Source tag & Order toggle)
        LinearLayout drawerTools = new LinearLayout(activity);
        drawerTools.setGravity(Gravity.CENTER_VERTICAL);
        drawerTools.setMinimumHeight(UIHelpers.dp(activity, 39));

        String sourceLabel = LocalModels.isDownload(book) ? "离线下载"
                : (LocalModels.FORMAT_PDF.equals(book.format) ? "PDF 导入"
                : (LocalModels.FORMAT_EPUB.equals(book.format) ? "EPUB 导入"
                : (LocalModels.isKindleFormat(book.format) ? book.format.toUpperCase(Locale.US) + " 导入" : "本地导入")));
        TextView drawerSource = UIHelpers.text(activity, sourceLabel, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        drawerTools.addView(drawerSource, UIHelpers.weight(1));

        final boolean[] desc = new boolean[]{false};
        TextView order = UIHelpers.text(activity, "正序", 11, UIHelpers.ACCENT, Typeface.BOLD);
        order.setGravity(Gravity.CENTER);
        order.setPadding(UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 8), UIHelpers.dp(activity, 4));
        drawerTools.addView(order);
        panel.addView(drawerTools, new LinearLayout.LayoutParams(-1, UIHelpers.dp(activity, 39)));
        panel.addView(UIHelpers.divider(activity));

        ScrollView scroll = new ScrollView(activity);
        scroll.setVerticalScrollBarEnabled(false);
        LinearLayout list = new LinearLayout(activity);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, new FrameLayout.LayoutParams(-1, -2));
        panel.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        int drawerWidth = Math.round(activity.getResources().getDisplayMetrics().widthPixels * 0.76f);
        PopupWindow popup = new PopupWindow(panel, drawerWidth, -1, true);
        popup.setBackgroundDrawable(new ColorDrawable(UIHelpers.CARD));
        popup.setOutsideTouchable(true);
        popup.setElevation(UIHelpers.dp(activity, 14));

        close.setOnClickListener(v -> popup.dismiss());

        java.util.Map<String, LocalModels.Volume> chapterVolumes = new java.util.HashMap<>();
        LocalLibraryStore localStore = LocalLibrary.get(activity).store;
        java.util.Map<String, LocalModels.Volume> volumesById = new java.util.HashMap<>();
        for (LocalModels.Volume volume : localStore.getVolumes(book.id)) volumesById.put(volume.id, volume);
        if (volumesById.size() > 1) for (LocalModels.Chapter chapter : localStore.getChapters(book.id)) {
            LocalModels.Volume volume = volumesById.get(chapter.volumeId);
            if (volume != null) chapterVolumes.put(chapter.id, volume);
        }
        final int[] renderGeneration = {0};
        Runnable render = () -> {
            int generation = ++renderGeneration[0];
            list.removeAllViews();
            List<Integer> orderIndexes = new ArrayList<>();
            for (int i = 0; i < detail.chapters.size(); i++) {
                orderIndexes.add(i);
            }
            if (desc[0]) {
                Collections.reverse(orderIndexes);
            }
            fillBatch(activity, list, popup, detail, orderIndexes, 0, generation, renderGeneration, targetChapter, hasRead, onSelect, chapterVolumes);
        };

        order.setOnClickListener(v -> {
            desc[0] = !desc[0];
            order.setText(desc[0] ? "倒序" : "正序");
            render.run();
        });

        popup.showAtLocation(rootLocation, Gravity.RIGHT, 0, 0);
        render.run();
    }

    private static void fillBatch(Activity activity, LinearLayout list, PopupWindow popup,
                                  ComicModels.ComicDetail detail, List<Integer> orderIndexes,
                                  int start, int generation, int[] renderGeneration,
                                  int targetChapter, boolean hasRead, OnChapterSelected onSelect,
                                  java.util.Map<String, LocalModels.Volume> chapterVolumes) {
        if (generation != renderGeneration[0] || !popup.isShowing()) return;
        int endIndex = Math.min(start + CHAPTER_DRAWER_BATCH_SIZE, orderIndexes.size());
        for (int i = start; i < endIndex; i++) {
            int chapterIndex = orderIndexes.get(i);
            ComicModels.Chapter ch = detail.chapters.get(chapterIndex);
            LocalModels.Volume volume = chapterVolumes.get(ch.chapterId);
            LocalModels.Volume previous = i == 0 ? null : chapterVolumes.get(detail.chapters.get(orderIndexes.get(i - 1)).chapterId);
            if (volume != null && (previous == null || !previous.id.equals(volume.id))) {
                TextView heading = UIHelpers.text(activity, volume.title, 12, UIHelpers.ACCENT, Typeface.BOLD);
                heading.setPadding(UIHelpers.dp(activity, 4), UIHelpers.dp(activity, 12), 0, UIHelpers.dp(activity, 6));
                list.addView(heading);
            }
            boolean isCurrent = hasRead && (chapterIndex == targetChapter);

            LinearLayout row = new LinearLayout(activity);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setMinimumHeight(UIHelpers.dp(activity, 38));
            row.setPadding(UIHelpers.dp(activity, 4), 0, UIHelpers.dp(activity, 4), 0);
            if (isCurrent) {
                row.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 5), Color.TRANSPARENT));
            }

            TextView name = UIHelpers.text(activity, ch.title, 14, isCurrent ? UIHelpers.ACCENT : UIHelpers.TEXT,
                    isCurrent ? Typeface.BOLD : Typeface.NORMAL);
            name.setSingleLine(true);
            name.setEllipsize(TextUtils.TruncateAt.END);
            row.addView(name, UIHelpers.weight(1));

            String endText = isCurrent ? "上次读到" : String.valueOf(chapterIndex + 1);
            if (!"local".equals(detail.summary.sourceId)) {
                com.xxcomic.download.DownloadModels.Task task = com.xxcomic.download.DownloadRuntime.get(activity).store.get(
                        com.xxcomic.download.DownloadModels.key(detail.summary.sourceId, detail.summary.comicId, ch.chapterId));
                if (!isCurrent) endText = task != null && task.state == com.xxcomic.download.DownloadModels.State.COMPLETED ? "已下载" : "在线";
            }
            TextView numView = UIHelpers.text(activity, endText, 11, isCurrent ? UIHelpers.ACCENT : UIHelpers.TEXT3, Typeface.NORMAL);
            numView.setGravity(Gravity.RIGHT | Gravity.CENTER_VERTICAL);
            row.addView(numView);

            row.setOnClickListener(v -> {
                popup.dismiss();
                if (onSelect != null) onSelect.onSelect(chapterIndex);
            });

            list.addView(row);
            if (i < orderIndexes.size() - 1) {
                list.addView(UIHelpers.divider(activity));
            }
        }

        if (endIndex < orderIndexes.size() && popup.isShowing()) {
            list.postDelayed(() -> fillBatch(activity, list, popup, detail, orderIndexes, endIndex,
                    generation, renderGeneration, targetChapter, hasRead, onSelect, chapterVolumes), 16);
        }
    }

    public static void showRenameDialog(Activity activity, LocalModels.Book book,
                                         LocalLibraryStore store, Listener listener) {
        if (activity == null || activity.isFinishing()) return;

        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 20),
                UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 18));
        layout.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 16), Color.TRANSPARENT));

        // Header with Rem avatar and title
        LinearLayout header = new LinearLayout(activity);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        ImageView remIcon = new ImageView(activity);
        remIcon.setImageResource(R.drawable.rem_reader_resume);
        remIcon.setScaleType(ImageView.ScaleType.CENTER_CROP);
        remIcon.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 18), Color.TRANSPARENT));
        remIcon.setClipToOutline(true);
        header.addView(remIcon, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 36), UIHelpers.dp(activity, 36)));

        LinearLayout headerText = new LinearLayout(activity);
        headerText.setOrientation(LinearLayout.VERTICAL);
        headerText.setPadding(UIHelpers.dp(activity, 12), 0, 0, 0);

        TextView titleView = UIHelpers.text(activity, "重命名漫画", 17, UIHelpers.TEXT, Typeface.BOLD);
        headerText.addView(titleView);

        TextView subView = UIHelpers.text(activity, "修改在 App 内显示的本地漫画名称", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        headerText.addView(subView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 2)));

        header.addView(headerText, UIHelpers.weight(1));
        layout.addView(header);

        // Input field
        final EditText input = new EditText(activity);
        input.setSingleLine(true);
        input.setText(book.getDisplayTitle());
        input.setSelection(input.getText().length());
        input.setTextColor(UIHelpers.TEXT);
        input.setTextSize(14);
        input.setHint("请输入漫画名称");
        input.setHintTextColor(UIHelpers.TEXT3);
        input.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 8), UIHelpers.BORDER));
        int padH = UIHelpers.dp(activity, 12);
        int padV = UIHelpers.dp(activity, 10);
        input.setPadding(padH, padV, padH, padV);
        layout.addView(input, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 16)));

        final TextView errorView = UIHelpers.text(activity, "", 11, UIHelpers.DANGER, Typeface.NORMAL);
        errorView.setVisibility(View.GONE);
        layout.addView(errorView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 4)));

        input.addTextChangedListener(new android.text.TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                if (errorView.getVisibility() == View.VISIBLE) {
                    errorView.setVisibility(View.GONE);
                }
            }
            @Override public void afterTextChanged(android.text.Editable s) {}
        });

        // Buttons
        LinearLayout btnRow = new LinearLayout(activity);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER_VERTICAL);

        Button cancelBtn = new Button(activity);
        cancelBtn.setText("取消");
        cancelBtn.setTextSize(14);
        cancelBtn.setTextColor(UIHelpers.TEXT2);
        cancelBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 8), UIHelpers.BORDER));
        cancelBtn.setOnClickListener(v -> dialog.dismiss());
        btnRow.addView(cancelBtn, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 40), 1f));

        btnRow.addView(UIHelpers.space(activity, UIHelpers.dp(activity, 10), 1));

        Button saveBtn = new Button(activity);
        saveBtn.setText("保存");
        saveBtn.setTextSize(14);
        saveBtn.setTypeface(Typeface.DEFAULT_BOLD);
        saveBtn.setTextColor(Color.WHITE);
        saveBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(activity, 8), Color.TRANSPARENT));
        saveBtn.setOnClickListener(v -> {
            String newTitle = input.getText().toString().trim();
            if (TextUtils.isEmpty(newTitle)) {
                errorView.setText("漫画名称不能为空");
                errorView.setVisibility(View.VISIBLE);
                return;
            }
            saveBtn.setEnabled(false);
            new Thread(() -> {
                LocalModels.Book renamed = null;
                try {
                    if (store.renameBook(book.id, newTitle)) renamed = store.getBook(book.id);
                } catch (Exception ignored) { }
                final LocalModels.Book updated = renamed;
                activity.runOnUiThread(() -> {
                    if (activity.isFinishing() || activity.isDestroyed()) return;
                    saveBtn.setEnabled(true);
                    if (updated == null) {
                        errorView.setText("名称保存失败，请重试");
                        errorView.setVisibility(View.VISIBLE);
                        return;
                    }
                    dialog.dismiss();
                    if (listener != null) {
                        listener.onBookRenamed(updated);
                        listener.showToast("已重命名漫画");
                    }
                });
            }, "local-rename").start();
        });
        btnRow.addView(saveBtn, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 40), 1f));

        layout.addView(btnRow, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 18)));

        dialog.setContentView(layout);

        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 48), UIHelpers.dp(activity, 320));
            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            window.setWindowAnimations(android.R.style.Animation_Dialog);
            window.setDimAmount(0.45f);
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE);
        }

        dialog.show();
        input.requestFocus();
    }

    public static void showDeleteDialog(Activity activity, LocalModels.Book book,
                                         LocalLibraryStore store, LocalStorageManager storageManager,
                                         Listener listener) {
        if (activity == null || activity.isFinishing()) return;

        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 20),
                UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 18));
        layout.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 16), Color.TRANSPARENT));

        LinearLayout body = new LinearLayout(activity);
        body.setOrientation(LinearLayout.HORIZONTAL);
        body.setGravity(Gravity.TOP);

        ImageView art = new ImageView(activity);
        art.setImageResource(R.drawable.rem_empty);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        body.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 52), UIHelpers.dp(activity, 52)));

        LinearLayout copy = new LinearLayout(activity);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 2), 0, 0);

        TextView titleView = UIHelpers.text(activity, "删除本地漫画？", 17, UIHelpers.TEXT, Typeface.BOLD);
        copy.addView(titleView);

        boolean isDownload = LocalModels.isDownload(book);
        String message = isDownload
                ? "将删除《" + book.getDisplayTitle() + "》的全部离线下载文件并释放 " + formatBytes(book.totalSize) + " 存储空间。\n\n收藏与阅读记录会保留，再次下载相同内容后可继续阅读。"
                : "将删除《" + book.getDisplayTitle() + "》在 App 内的副本并释放 " + formatBytes(book.totalSize) + " 存储空间。\n\n提示：您手机上的原始文件不受影响。阅读进度已保留，日后重导可继续阅读。";
        TextView messageView = UIHelpers.text(activity, message, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 6)));
        body.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        layout.addView(body);

        LinearLayout btnRow = new LinearLayout(activity);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER_VERTICAL);

        Button cancelBtn = new Button(activity);
        cancelBtn.setText("取消");
        cancelBtn.setTextSize(14);
        cancelBtn.setTextColor(UIHelpers.TEXT2);
        cancelBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 8), UIHelpers.BORDER));
        cancelBtn.setOnClickListener(v -> dialog.dismiss());
        btnRow.addView(cancelBtn, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 40), 1f));

        btnRow.addView(UIHelpers.space(activity, UIHelpers.dp(activity, 10), 1));

        Button delBtn = new Button(activity);
        delBtn.setText("确认删除");
        delBtn.setTextSize(14);
        delBtn.setTypeface(Typeface.DEFAULT_BOLD);
        delBtn.setTextColor(Color.WHITE);
        delBtn.setBackground(UIHelpers.round(UIHelpers.DANGER, UIHelpers.dp(activity, 8), Color.TRANSPARENT));
        delBtn.setOnClickListener(v -> {
            dialog.dismiss();
            executeDelete(activity, book, store, storageManager, listener);
        });
        btnRow.addView(delBtn, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 40), 1f));

        layout.addView(btnRow, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 18)));

        dialog.setContentView(layout);

        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 48), UIHelpers.dp(activity, 320));
            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            window.setWindowAnimations(android.R.style.Animation_Dialog);
            window.setDimAmount(0.45f);
        }

        dialog.show();
    }

    private static void executeDelete(Activity activity, LocalModels.Book book,
                                      LocalLibraryStore store, LocalStorageManager storageManager,
                                      Listener listener) {
        new Thread(() -> {
            boolean deleted;
            try { deleted = LocalModels.isDownload(book)
                    ? com.xxcomic.download.DownloadRuntime.get(activity).deleteBook(book.id) : store.deleteBook(book.id, storageManager); }
            catch (Exception error) { deleted = false; }
            final boolean success = deleted;

            if (activity != null) {
                activity.runOnUiThread(() -> {
                    if (activity.isFinishing()) return;
                    if (success) {
                        if (listener != null) {
                            listener.showToast("已删除本地漫画");
                            listener.onBookDeleted(book);
                        }
                    } else {
                        Dialog retryDialog = new Dialog(activity);
                        retryDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

                        LinearLayout layout = new LinearLayout(activity);
                        layout.setOrientation(LinearLayout.VERTICAL);
                        layout.setPadding(UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 20),
                                UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 18));
                        layout.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 16), Color.TRANSPARENT));

                        LinearLayout body = new LinearLayout(activity);
                        body.setOrientation(LinearLayout.HORIZONTAL);
                        body.setGravity(Gravity.TOP);

                        ImageView art = new ImageView(activity);
                        art.setImageResource(R.drawable.rem_error);
                        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
                        body.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 52), UIHelpers.dp(activity, 52)));

                        LinearLayout copy = new LinearLayout(activity);
                        copy.setOrientation(LinearLayout.VERTICAL);
                        copy.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 2), 0, 0);

                        TextView titleView = UIHelpers.text(activity, "删除未完全完成", 17, UIHelpers.TEXT, Typeface.BOLD);
                        copy.addView(titleView);

                        TextView messageView = UIHelpers.text(activity, "部分漫画文件未能完全清理，建议稍后重试。", 12, UIHelpers.TEXT2, Typeface.NORMAL);
                        copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 6)));
                        body.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

                        layout.addView(body);

                        LinearLayout btnRow = new LinearLayout(activity);
                        btnRow.setOrientation(LinearLayout.HORIZONTAL);
                        btnRow.setGravity(Gravity.CENTER_VERTICAL);

                        Button cancelBtn = new Button(activity);
                        cancelBtn.setText("取消");
                        cancelBtn.setTextSize(14);
                        cancelBtn.setTextColor(UIHelpers.TEXT2);
                        cancelBtn.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 8), UIHelpers.BORDER));
                        cancelBtn.setOnClickListener(v -> retryDialog.dismiss());
                        btnRow.addView(cancelBtn, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 40), 1f));

                        btnRow.addView(UIHelpers.space(activity, UIHelpers.dp(activity, 10), 1));

                        Button retryBtn = new Button(activity);
                        retryBtn.setText("重试");
                        retryBtn.setTextSize(14);
                        retryBtn.setTypeface(Typeface.DEFAULT_BOLD);
                        retryBtn.setTextColor(Color.WHITE);
                        retryBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT, UIHelpers.dp(activity, 8), Color.TRANSPARENT));
                        retryBtn.setOnClickListener(v -> {
                            retryDialog.dismiss();
                            executeDelete(activity, book, store, storageManager, listener);
                        });
                        btnRow.addView(retryBtn, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 40), 1f));

                        layout.addView(btnRow, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 18)));

                        retryDialog.setContentView(layout);

                        Window window = retryDialog.getWindow();
                        if (window != null) {
                            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
                            int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 48), UIHelpers.dp(activity, 320));
                            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
                            window.setWindowAnimations(android.R.style.Animation_Dialog);
                            window.setDimAmount(0.45f);
                        }
                        retryDialog.show();
                    }
                });
            }
        }).start();
    }

    private static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        char unit = "KMGTPE".charAt(exp - 1);
        return String.format(Locale.US, "%.1f %cB", bytes / Math.pow(1024, exp), unit);
    }
}
