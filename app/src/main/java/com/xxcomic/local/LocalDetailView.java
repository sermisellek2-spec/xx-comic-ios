package com.xxcomic.local;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
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

        TextView more = UIHelpers.text(activity, "···", 22, Color.WHITE, Typeface.BOLD);
        more.setGravity(Gravity.CENTER);
        more.setContentDescription("更多操作");
        more.setOnClickListener(v -> {
            LinearLayout menu = new LinearLayout(activity);
            menu.setOrientation(LinearLayout.VERTICAL);
            menu.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 8), UIHelpers.BORDER));
            PopupWindow popup = new PopupWindow(menu, UIHelpers.dp(activity, 140), -2, true);
            popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            popup.setOutsideTouchable(true);
            popup.setElevation(UIHelpers.dp(activity, 8));
            String[] labels = {"重命名", "删除漫画"};
            for (int i = 0; i < labels.length; i++) {
                final int action = i;
                TextView item = UIHelpers.text(activity, labels[i], 14, UIHelpers.TEXT, Typeface.NORMAL);
                item.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 14), UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 14));
                item.setOnClickListener(clicked -> {
                    popup.dismiss();
                    if (action == 0) showRenameDialog(activity, book, store, listener);
                    else showDeleteDialog(activity, book, store, storageManager, listener);
                });
                menu.addView(item, new LinearLayout.LayoutParams(-1, -2));
            }
            popup.showAsDropDown(more, 0, 0, Gravity.END);
        });
        topBar.addView(more, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 44), UIHelpers.dp(activity, 44)));

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

        TextView formatBadge = UIHelpers.text(activity, LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) ? "离线" : book.format.toUpperCase(Locale.US), 11, UIHelpers.ACCENT, Typeface.BOLD);
        formatBadge.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, UIHelpers.dp(activity, 4), UIHelpers.BORDER));
        formatBadge.setPadding(UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 3), UIHelpers.dp(activity, 6), UIHelpers.dp(activity, 3));
        titleRow.addView(formatBadge);

        body.addView(titleRow);

        // Metadata
        String metaText = (LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) ? "离线下载 · " : "本地导入 · ") + formatBytes(book.totalSize) + " · 共 " + book.chapterCount + " 话 / " + book.pageCount + " 页";
        TextView metaView = UIHelpers.text(activity, metaText, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        body.addView(metaView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 8)));

        // File path info
        TextView fileInfo = UIHelpers.text(activity, "储存路径: " + book.relativePath, 11, UIHelpers.TEXT3, Typeface.NORMAL);
        fileInfo.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        fileInfo.setSingleLine(true);
        body.addView(fileInfo, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 4)));

        // Reading Action Button
        final int targetChapter = Math.max(0, Math.min(savedChapterIndex, detail.chapters.size() - 1));
        String readActionText = hasRead ? "继续阅读 第 " + (targetChapter + 1) + " 话" : "开始阅读";
        Button readBtn = UIHelpers.primaryButton(activity, readActionText);
        readBtn.setOnClickListener(v -> {
            if (listener != null) listener.onRead(book, detail, targetChapter);
        });
        body.addView(readBtn, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 14), -1, UIHelpers.dp(activity, 44)));

        // Divider
        body.addView(UIHelpers.divider(activity), UIHelpers.marginTop(-1, UIHelpers.dp(activity, 16)));

        // 3. Chapter Entry (Opens 76% Drawer)
        View chapterEntryView = buildChapterEntry(activity, root, book, detail, targetChapter, hasRead, (selectedChapter) -> {
            if (listener != null) listener.onRead(book, detail, selectedChapter);
        });
        body.addView(chapterEntryView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 12)));

        return root;
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
        String sourceTag = LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) ? "离线下载" : "本地漫画";
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

        String sourceLabel = LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType) ? "离线下载" : "本地导入";
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
            fillBatch(activity, list, popup, detail, orderIndexes, 0, generation, renderGeneration, targetChapter, hasRead, onSelect);
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
                                  int targetChapter, boolean hasRead, OnChapterSelected onSelect) {
        if (generation != renderGeneration[0] || !popup.isShowing()) return;
        int endIndex = Math.min(start + CHAPTER_DRAWER_BATCH_SIZE, orderIndexes.size());
        for (int i = start; i < endIndex; i++) {
            int chapterIndex = orderIndexes.get(i);
            ComicModels.Chapter ch = detail.chapters.get(chapterIndex);
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
                    generation, renderGeneration, targetChapter, hasRead, onSelect), 16);
        }
    }

    public static void showRenameDialog(Activity activity, LocalModels.Book book,
                                         LocalLibraryStore store, Listener listener) {
        if (activity == null || activity.isFinishing()) return;

        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 16),
                UIHelpers.dp(activity, 20), UIHelpers.dp(activity, 12));

        TextView titleView = UIHelpers.text(activity, "重命名漫画", 17, UIHelpers.TEXT, Typeface.BOLD);
        layout.addView(titleView);

        TextView subView = UIHelpers.text(activity, "修改在 App 内显示的本地漫画名称", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        layout.addView(subView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 4)));

        final EditText input = new EditText(activity);
        input.setSingleLine(true);
        input.setText(book.getDisplayTitle());
        input.setSelection(input.getText().length());
        input.setTextColor(UIHelpers.TEXT);
        input.setHintTextColor(UIHelpers.TEXT3);
        input.setBackground(UIHelpers.round(UIHelpers.SURFACE, UIHelpers.dp(activity, 8), UIHelpers.BORDER));
        int pad = UIHelpers.dp(activity, 10);
        input.setPadding(pad, pad, pad, pad);
        layout.addView(input, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 14)));

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

        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setView(layout)
                .setPositiveButton("保存", null)
                .setNegativeButton("取消", null)
                .create();

        dialog.setOnShowListener(d -> {
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 12), Color.TRANSPARENT));
                int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 40), UIHelpers.dp(activity, 328));
                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            }
            Button pos = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            if (pos != null) {
                pos.setTextColor(UIHelpers.ACCENT);
                pos.setOnClickListener(v -> {
                    String newTitle = input.getText().toString().trim();
                    if (TextUtils.isEmpty(newTitle)) {
                        errorView.setText("漫画名称不能为空");
                        errorView.setVisibility(View.VISIBLE);
                        return;
                    }
                    pos.setEnabled(false);
                    new Thread(() -> {
                        LocalModels.Book renamed = null;
                        try {
                            if (store.renameBook(book.id, newTitle)) renamed = store.getBook(book.id);
                        } catch (Exception ignored) { }
                        final LocalModels.Book updated = renamed;
                        activity.runOnUiThread(() -> {
                            if (activity.isFinishing() || activity.isDestroyed()) return;
                            pos.setEnabled(true);
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
            }
            Button neg = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (neg != null) neg.setTextColor(UIHelpers.TEXT3);
        });

        dialog.show();
    }

    public static void showDeleteDialog(Activity activity, LocalModels.Book book,
                                         LocalLibraryStore store, LocalStorageManager storageManager,
                                         Listener listener) {
        if (activity == null || activity.isFinishing()) return;

        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.HORIZONTAL);
        content.setGravity(Gravity.TOP);
        content.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16),
                UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 10));

        ImageView art = new ImageView(activity);
        art.setImageResource(R.drawable.rem_empty);
        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
        content.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 56), UIHelpers.dp(activity, 56)));

        LinearLayout copy = new LinearLayout(activity);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 2), 0, 0);

        TextView titleView = UIHelpers.text(activity, "删除本地漫画？", 17, UIHelpers.TEXT, Typeface.BOLD);
        copy.addView(titleView);

        boolean isDownload = LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType);
        String message = isDownload
                ? "将删除《" + book.getDisplayTitle() + "》的全部离线下载文件并释放 " + formatBytes(book.totalSize) + " 存储空间。\n\n提示：在线收藏与阅读进度已保留，之后仍可在联网时继续阅读。"
                : "将删除《" + book.getDisplayTitle() + "》在 App 内的副本并释放 " + formatBytes(book.totalSize) + " 存储空间。\n\n提示：您手机上的原始文件不受影响。阅读进度已保留，日后重导可继续阅读。";
        TextView messageView = UIHelpers.text(activity, message, 12, UIHelpers.TEXT2, Typeface.NORMAL);
        copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 6)));
        content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setView(content)
                .setPositiveButton("删除", (d, which) -> executeDelete(activity, book, store, storageManager, listener))
                .setNegativeButton("取消", null)
                .create();

        dialog.setOnShowListener(d -> {
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 12), Color.TRANSPARENT));
                int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 40), UIHelpers.dp(activity, 328));
                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
            }
            Button pos = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            if (pos != null) pos.setTextColor(UIHelpers.DANGER);
            Button neg = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (neg != null) neg.setTextColor(UIHelpers.TEXT3);
        });

        dialog.show();
    }

    private static void executeDelete(Activity activity, LocalModels.Book book,
                                      LocalLibraryStore store, LocalStorageManager storageManager,
                                      Listener listener) {
        new Thread(() -> {
            boolean deleted;
            try { deleted = LocalModels.SOURCE_TYPE_DOWNLOAD.equals(book.sourceType)
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
                        // Retention of deleting tombstone allows retry without faking success
                        LinearLayout content = new LinearLayout(activity);
                        content.setOrientation(LinearLayout.HORIZONTAL);
                        content.setGravity(Gravity.TOP);
                        content.setPadding(UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 16),
                                UIHelpers.dp(activity, 16), UIHelpers.dp(activity, 10));

                        ImageView art = new ImageView(activity);
                        art.setImageResource(R.drawable.rem_error);
                        art.setScaleType(ImageView.ScaleType.FIT_CENTER);
                        content.addView(art, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 56), UIHelpers.dp(activity, 56)));

                        LinearLayout copy = new LinearLayout(activity);
                        copy.setOrientation(LinearLayout.VERTICAL);
                        copy.setPadding(UIHelpers.dp(activity, 12), UIHelpers.dp(activity, 2), 0, 0);

                        TextView titleView = UIHelpers.text(activity, "删除未完全完成", 17, UIHelpers.TEXT, Typeface.BOLD);
                        copy.addView(titleView);

                        TextView messageView = UIHelpers.text(activity, "部分漫画文件未能完全清理，建议稍后重试。", 12, UIHelpers.TEXT2, Typeface.NORMAL);
                        copy.addView(messageView, UIHelpers.marginTop(-1, UIHelpers.dp(activity, 6)));
                        content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

                        AlertDialog retryDialog = new AlertDialog.Builder(activity)
                                .setView(content)
                                .setPositiveButton("重试", (d, w) -> executeDelete(activity, book, store, storageManager, listener))
                                .setNegativeButton("取消", null)
                                .create();
                        retryDialog.setOnShowListener(d -> {
                            android.view.Window window = retryDialog.getWindow();
                            if (window != null) {
                                window.setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 12), Color.TRANSPARENT));
                                int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - UIHelpers.dp(activity, 40), UIHelpers.dp(activity, 328));
                                window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
                            }
                            Button pos = retryDialog.getButton(AlertDialog.BUTTON_POSITIVE);
                            if (pos != null) pos.setTextColor(UIHelpers.ACCENT);
                            Button neg = retryDialog.getButton(AlertDialog.BUTTON_NEGATIVE);
                            if (neg != null) neg.setTextColor(UIHelpers.TEXT3);
                        });
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
