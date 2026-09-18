package com.xxcomic.download;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.ArrayAdapter;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import com.xxcomic.R;
import com.xxcomic.UIHelpers;
import com.xxcomic.local.LocalLibrary;
import com.xxcomic.local.LocalModels;
import com.xxcomic.source.ComicModels;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import static com.xxcomic.download.DownloadModels.*;

/** Native themed lists; recycled chapter rows keep very large directories responsive. */
public final class DownloadViews {
    public interface OpenBook { void accept(String bookId); }
    private static boolean hasNewRevision(Task task,List<com.xxcomic.source.FileResource> files) {
        if(files==null || task.state!=State.COMPLETED)return false;
        for(com.xxcomic.source.FileResource f:files)if(f.fileId.equals(task.fileId))
            return !java.util.Objects.equals(f.revision,task.revision) || !java.util.Objects.equals(f.sha256,task.sha256);
        return false;
    }

    public static void selection(Activity a, ComicModels.ComicDetail detail, int current, Runnable onAdded) {
        selection(a,detail,current,onAdded,null,null,null);
    }
    public static void fileSelection(Activity a, ComicModels.ComicDetail detail, List<com.xxcomic.source.FileResource> files,
                                     OpenBook open, Runnable center) {
        files=new ArrayList<>(files);
        Collections.sort(files,(left,right)->Integer.compare(left.order,right.order));
        List<ComicModels.Chapter> volumes=new ArrayList<>();
        for(com.xxcomic.source.FileResource file:files)volumes.add(new ComicModels.Chapter(file.fileId,file.title,"",file.order,0));
        selection(a,new ComicModels.ComicDetail(detail.summary,detail.author,detail.status,detail.description,
                "",volumes),0,center,files,open,center);
    }
    private static void selection(Activity a, ComicModels.ComicDetail detail, int current, Runnable onAdded,
                                  List<com.xxcomic.source.FileResource> files, OpenBook open, Runnable center) {
        DownloadRuntime runtime = DownloadRuntime.get(a);
        Set<String> selected = new LinkedHashSet<>();
        if (!detail.chapters.isEmpty()) {
            selected.add(detail.chapters.get(Math.max(0, Math.min(current, detail.chapters.size() - 1))).chapterId);
        }

        Dialog dialog = new Dialog(a);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout panel = column(a);
        panel.setPadding(dp(a, 16), dp(a, 14), dp(a, 16), dp(a, 14));
        panel.setBackground(UIHelpers.round(UIHelpers.CARD, dp(a, 18), Color.TRANSPARENT));

        // Header row with title and close button
        LinearLayout headerRow = row(a);
        LinearLayout headerTextCol = column(a);
        headerTextCol.addView(UIHelpers.text(a, "下载到本地书架", 18, UIHelpers.TEXT, Typeface.BOLD));
        String wifiHint = "仅保存本次选择的章节 · " + (runtime.wifiOnly() ? "仅 Wi-Fi" : "允许移动网络");
        headerTextCol.addView(UIHelpers.text(a, wifiHint, 12, UIHelpers.TEXT3, Typeface.NORMAL), UIHelpers.marginTop(-1, dp(a, 2)));
        headerRow.addView(headerTextCol, UIHelpers.weight(1));

        panel.addView(headerRow);

        // Tool chips: 本章, 全选, 清空, 倒序
        LinearLayout tools = row(a);
        tools.setPadding(0, dp(a, 10), 0, dp(a, 8));
        panel.addView(tools);

        ListView list = new ListView(a);
        list.setDivider(new ColorDrawable(UIHelpers.BORDER));
        list.setDividerHeight(1);
        List<ComicModels.Chapter> visible = new ArrayList<>(detail.chapters);

        Button start = UIHelpers.primaryButton(a, "下载选中章节 (" + selected.size() + ")");

        BaseAdapter adapter = new BaseAdapter() {
            @Override public int getCount() { return visible.size(); }
            @Override public Object getItem(int i) { return visible.get(i); }
            @Override public long getItemId(int i) { return i; }
            @Override public View getView(int i, View recycled, ViewGroup parent) {
                CheckBox check = recycled instanceof CheckBox ? (CheckBox) recycled : new CheckBox(a);
                ComicModels.Chapter ch = visible.get(i);
                Task task = runtime.store.get(files==null?key(detail.summary.sourceId, detail.summary.comicId, ch.chapterId)
                        :fileTaskId(detail.summary.sourceId,detail.summary.comicId,ch.chapterId));
                boolean exists = task != null && !hasNewRevision(task,files);
                check.setOnCheckedChangeListener(null);
                check.setText(ch.title + (exists ? " · " + state(task) : ""));
                check.setTextSize(13);
                check.setTextColor(exists ? UIHelpers.TEXT3 : UIHelpers.TEXT);
                check.setMinHeight(dp(a, 46));
                check.setPadding(dp(a, 6), dp(a, 4), dp(a, 6), dp(a, 4));
                check.setButtonTintList(ColorStateList.valueOf(UIHelpers.ACCENT));
                check.setOnClickListener(null);
                check.setEnabled(!exists || files!=null);
                check.setChecked(!exists && selected.contains(ch.chapterId));
                check.setOnCheckedChangeListener((button, value) -> {
                    if(exists)return;
                    if (value) selected.add(ch.chapterId);
                    else selected.remove(ch.chapterId);
                    start.setText("下载选中章节 (" + selected.size() + ")");
                });
                if(exists && files!=null)check.setOnClickListener(v->{dialog.dismiss();
                    if(runtime.library.store.getBook(task.bookId)!=null)open.accept(task.bookId);else center.run();});
                return check;
            }
        };
        list.setAdapter(adapter);

        addToolChip(a, tools, "本章", () -> {
            selected.clear();
            if (!detail.chapters.isEmpty()) {
                selected.add(detail.chapters.get(Math.max(0, Math.min(current, detail.chapters.size() - 1))).chapterId);
            }
            start.setText("下载选中章节 (" + selected.size() + ")");
            adapter.notifyDataSetChanged();
        });
        addToolChip(a, tools, "全选", () -> {
            for (ComicModels.Chapter ch : detail.chapters) selected.add(ch.chapterId);
            start.setText("下载选中章节 (" + selected.size() + ")");
            adapter.notifyDataSetChanged();
        });
        addToolChip(a, tools, "清空", () -> {
            selected.clear();
            start.setText("下载选中章节 (0)");
            adapter.notifyDataSetChanged();
        });
        addToolChip(a, tools, "倒序 ⇄", () -> {
            Collections.reverse(visible);
            adapter.notifyDataSetChanged();
        });

        panel.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout.LayoutParams startParams = new LinearLayout.LayoutParams(-1, dp(a, 46));
        startParams.topMargin = dp(a, 10);
        panel.addView(start, startParams);

        start.setOnClickListener(v -> {
            List<String> ids = new ArrayList<>();
            for (String id : selected) {
                Task found=runtime.store.get(files==null?key(detail.summary.sourceId,detail.summary.comicId,id)
                        :fileTaskId(detail.summary.sourceId,detail.summary.comicId,id));
                if (found == null || hasNewRevision(found,files)) {
                    ids.add(id);
                }
            }
            if (ids.isEmpty()) {
                toast(a, "先选择未下载的章节哦");
                return;
            }
            start.setEnabled(false);
            runtime.io.execute(() -> {
                try {
                    if(files==null)runtime.enqueue(detail, ids);else runtime.enqueueFiles(detail,files,ids);
                    a.runOnUiThread(() -> {
                        if (a.isDestroyed()) return;
                        dialog.dismiss();
                        startService(a);
                        toast(a, "已加入下载队列");
                        onAdded.run();
                    });
                } catch (Exception error) {
                    a.runOnUiThread(() -> {
                        if (a.isDestroyed()) return;
                        start.setEnabled(true);
                        toast(a, "无法创建下载任务，请重试");
                    });
                }
            });
        });

        dialog.setContentView(panel);
        dialog.show();
        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawableResource(android.R.color.transparent);
            w.setGravity(Gravity.BOTTOM);
            w.setLayout(-1, (int) (a.getResources().getDisplayMetrics().heightPixels * 0.76f));
            w.setDimAmount(0.28f);
            w.setWindowAnimations(R.style.DownloadSheetAnimation);
        }
    }

    public static void startService(Activity a) {
        try {
            DownloadService.start(a);
        } catch (RuntimeException error) {
            toast(a, "后台下载暂时无法启动，请回到 App 后重试");
        }
        if (Build.VERSION.SDK_INT >= 33
                && a.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
                && !a.getPreferences(0).getBoolean("downloads.notificationAsked", false)) {
            a.getPreferences(0).edit().putBoolean("downloads.notificationAsked", true).apply();
            a.requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 2302);
        }
    }

    public static View center(Activity a, Runnable back, OpenBook read, Runnable verify) {
        DownloadRuntime runtime = DownloadRuntime.get(a);
        LinearLayout page = column(a);
        page.setBackgroundColor(UIHelpers.BG);
        page.setPadding(dp(a, 16), dp(a, 12), dp(a, 16), dp(a, 16));

        header(a, page, "下载中心", back);

        // Action buttons: 全部暂停 & 继续下载
        LinearLayout tools = row(a);
        tools.setPadding(0, dp(a, 8), 0, dp(a, 8));
        Button pauseBtn = UIHelpers.secondaryButton(a, "全部暂停");
        pauseBtn.setOnClickListener(v -> runtime.pauseAll());
        tools.addView(pauseBtn, UIHelpers.buttonWeight(a, 1));
        tools.addView(UIHelpers.space(a, dp(a, 8), 1));
        Button resumeBtn = UIHelpers.primaryButton(a, "继续下载");
        resumeBtn.setOnClickListener(v -> {
            runtime.resumeAll();
            startService(a);
        });
        tools.addView(resumeBtn, UIHelpers.buttonWeight(a, 1));
        page.addView(tools);

        // Rem hint banner
        LinearLayout remRow = row(a);
        remRow.setPadding(dp(a, 12), dp(a, 8), dp(a, 12), dp(a, 8));
        remRow.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(a, 8), UIHelpers.BORDER));

        ImageView rem = new ImageView(a);
        rem.setImageResource(R.drawable.rem_reader_resume);
        rem.setScaleType(ImageView.ScaleType.CENTER_CROP);
        rem.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(a, 10), UIHelpers.BORDER));
        rem.setClipToOutline(true);
        remRow.addView(rem, new LinearLayout.LayoutParams(dp(a, 36), dp(a, 36)));

        TextView hint = UIHelpers.text(a, "蕾姆会把完整章节收进本地书架", 12, UIHelpers.TEXT2, Typeface.NORMAL);
        hint.setPadding(dp(a, 10), 0, 0, 0);
        remRow.addView(hint, new LinearLayout.LayoutParams(0, -2, 1));

        LinearLayout.LayoutParams remParams = new LinearLayout.LayoutParams(-1, -2);
        remParams.topMargin = dp(a, 4);
        remParams.bottomMargin = dp(a, 10);
        page.addView(remRow, remParams);

        // Empty state view
        LinearLayout emptyView = column(a);
        emptyView.setGravity(Gravity.CENTER);
        emptyView.setPadding(0, dp(a, 40), 0, dp(a, 40));
        ImageView emptyArt = new ImageView(a);
        emptyArt.setImageResource(R.drawable.rem_empty);
        emptyArt.setScaleType(ImageView.ScaleType.FIT_CENTER);
        emptyView.addView(emptyArt, new LinearLayout.LayoutParams(dp(a, 72), dp(a, 72)));
        TextView emptyTitle = UIHelpers.text(a, "暂无离线下载任务", 15, UIHelpers.TEXT, Typeface.BOLD);
        emptyView.addView(emptyTitle, UIHelpers.marginTop(-2, dp(a, 8)));
        TextView emptyDesc = UIHelpers.text(a, "可以在漫画详情页点击「下载离线章节」添加离线内容", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        emptyDesc.setGravity(Gravity.CENTER);
        emptyView.addView(emptyDesc, UIHelpers.marginTop(-2, dp(a, 4)));
        emptyView.setVisibility(View.GONE);
        page.addView(emptyView, new LinearLayout.LayoutParams(-1, 0, 1));

        List<String> books = new ArrayList<>();
        Map<String, List<Task>> groups = new LinkedHashMap<>();
        Map<String, String> titles = new HashMap<>();

        ListView list = new ListView(a);
        list.setDivider(null);
        list.setDividerHeight(dp(a, 8));
        list.setVerticalScrollBarEnabled(false);
        page.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));

        BaseAdapter adapter = new BaseAdapter() {
            @Override public int getCount() { return books.size(); }
            @Override public Object getItem(int i) { return books.get(i); }
            @Override public long getItemId(int i) { return i; }
            @Override public View getView(int i, View view, ViewGroup parent) {
                String id = books.get(i);
                List<Task> tasks = groups.get(id);

                LinearLayout card = row(a);
                card.setPadding(dp(a, 14), dp(a, 12), dp(a, 12), dp(a, 12));
                card.setBackground(UIHelpers.round(UIHelpers.CARD, dp(a, 10), UIHelpers.BORDER));

                LinearLayout copy = column(a);
                String displayTitle = titles.containsKey(id) ? titles.get(id) : "离线漫画";
                TextView titleView = UIHelpers.text(a, displayTitle, 15, UIHelpers.TEXT, Typeface.BOLD);
                titleView.setSingleLine(true);
                titleView.setEllipsize(TextUtils.TruncateAt.END);
                copy.addView(titleView);

                int done = 0;
                long bytes = 0;
                String current = "";
                if (tasks != null) {
                    for (Task t : tasks) {
                        if (t.state == State.COMPLETED) done++;
                        else current = state(t);
                        bytes += t.bytes;
                    }
                }
                int totalChapters = tasks != null ? tasks.size() : 0;
                String info = done + " / " + totalChapters + " 章 · " + format(bytes) + (current.isEmpty() ? "" : " · " + current);
                TextView subView = UIHelpers.text(a, info, 12, UIHelpers.TEXT3, Typeface.NORMAL);
                copy.addView(subView, UIHelpers.marginTop(-1, dp(a, 3)));
                card.addView(copy, UIHelpers.weight(1));

                ImageView chevron = UIHelpers.vectorIconButton(a, R.drawable.ic_chevron_right, UIHelpers.TEXT3, 3);
                card.addView(chevron, new LinearLayout.LayoutParams(dp(a, 24), dp(a, 24)));

                card.setOnClickListener(v -> taskSheet(a, id, read, verify));
                return card;
            }
        };
        list.setAdapter(adapter);

        Runnable refresh = new Runnable() {
            @Override public void run() {
                Map<String, String> cached = new HashMap<>(titles);
                runtime.io.execute(() -> {
                    Map<String, List<Task>> next = new LinkedHashMap<>();
                    for (Task t : runtime.store.list()) {
                        List<Task> g = next.get(t.bookId);
                        if (g == null) {
                            g = new ArrayList<>();
                            next.put(t.bookId, g);
                        }
                        g.add(t);
                    }
                    for (String id : next.keySet()) {
                        if (!cached.containsKey(id)) {
                            ComicModels.ComicDetail detail = runtime.store.snapshot(id);
                            Task first=next.get(id).get(0);
                            if(detail==null && first.isFileTask)detail=runtime.store.snapshot(bookId(first.sourceId,first.comicId));
                            cached.put(id, (detail == null ? "离线漫画" : detail.summary.title)+(first.isFileTask?" · "+first.title:""));
                        }
                    }
                    a.runOnUiThread(() -> {
                        if (!page.isAttachedToWindow() || a.isDestroyed()) return;
                        groups.clear();
                        groups.putAll(next);
                        titles.clear();
                        titles.putAll(cached);
                        books.clear();
                        books.addAll(groups.keySet());

                        if (books.isEmpty()) {
                            emptyView.setVisibility(View.VISIBLE);
                            list.setVisibility(View.GONE);
                            hint.setText("还没有下载任务，去漫画详情选择章节吧");
                        } else {
                            emptyView.setVisibility(View.GONE);
                            list.setVisibility(View.VISIBLE);
                            hint.setText("蕾姆会把完整章节收进本地书架");
                        }
                        adapter.notifyDataSetChanged();
                        page.postDelayed(this, 1500);
                    });
                });
            }
        };

        page.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View v) { page.post(refresh); }
            @Override public void onViewDetachedFromWindow(View v) { page.removeCallbacks(refresh); }
        });

        return page;
    }

    private static void taskSheet(Activity a, String bookId, OpenBook read, Runnable verify) {
        DownloadRuntime runtime = DownloadRuntime.get(a);
        List<Task> tasks = new ArrayList<>();

        Dialog dialog = new Dialog(a);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout panel = column(a);
        panel.setPadding(dp(a, 16), dp(a, 14), dp(a, 16), dp(a, 14));
        panel.setBackground(UIHelpers.round(UIHelpers.CARD, dp(a, 18), Color.TRANSPARENT));

        // Header
        LinearLayout headerRow = row(a);
        TextView titleView = UIHelpers.text(a, "章节下载详情", 17, UIHelpers.TEXT, Typeface.BOLD);
        headerRow.addView(titleView, UIHelpers.weight(1));

        panel.addView(headerRow);

        // Actions: 阅读 & 去验证
        LinearLayout tools = row(a);
        tools.setPadding(0, dp(a, 8), 0, dp(a, 8));
        addToolChip(a, tools, "阅读此书", () -> {
            dialog.dismiss();
            read.accept(bookId);
        });
        addToolChip(a, tools, "去验证", () -> {
            dialog.dismiss();
            verify.run();
        });
        panel.addView(tools);

        ListView list = new ListView(a);
        list.setDivider(new ColorDrawable(UIHelpers.BORDER));
        list.setDividerHeight(1);
        panel.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));

        BaseAdapter adapter = new BaseAdapter() {
            @Override public int getCount() { return tasks.size(); }
            @Override public Object getItem(int i) { return tasks.get(i); }
            @Override public long getItemId(int i) { return i; }
            @Override public View getView(int i, View old, ViewGroup parent) {
                Task task = tasks.get(i);
                LinearLayout row = row(a);
                row.setGravity(Gravity.CENTER_VERTICAL);
                row.setMinimumHeight(dp(a, 52));
                row.setPadding(dp(a, 4), dp(a, 4), dp(a, 4), dp(a, 4));

                LinearLayout textCol = column(a);
                TextView name = UIHelpers.text(a, task.title, 14, UIHelpers.TEXT, Typeface.NORMAL);
                name.setSingleLine(true);
                name.setEllipsize(TextUtils.TruncateAt.END);
                textCol.addView(name);

                String progressText = state(task) + " · " + task.donePages + " / " + task.totalPages + " 页"
                        + (task.error.isEmpty() ? "" : " · " + task.error);
                int statusColor = task.state == State.COMPLETED ? UIHelpers.ACCENT
                        : (task.state == State.FAILED ? UIHelpers.DANGER : UIHelpers.TEXT3);
                TextView sub = UIHelpers.text(a, progressText, 11, statusColor, Typeface.NORMAL);
                textCol.addView(sub, UIHelpers.marginTop(-1, dp(a, 2)));

                row.addView(textCol, UIHelpers.weight(1));

                ImageView actionIcon = UIHelpers.vectorIconButton(a, R.drawable.ic_chevron_right, UIHelpers.TEXT3, 4);
                row.addView(actionIcon, new LinearLayout.LayoutParams(dp(a, 24), dp(a, 24)));

                row.setOnClickListener(v -> taskActions(a, task));
                return row;
            }
        };
        list.setAdapter(adapter);

        dialog.setContentView(panel);
        dialog.show();

        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawableResource(android.R.color.transparent);
            w.setGravity(Gravity.BOTTOM);
            w.setLayout(-1, (int) (a.getResources().getDisplayMetrics().heightPixels * 0.76f));
            w.setDimAmount(0.28f);
            w.setWindowAnimations(R.style.DownloadSheetAnimation);
        }

        Runnable refresh = new Runnable() {
            @Override public void run() {
                runtime.io.execute(() -> {
                    List<Task> next = new ArrayList<>();
                    for (Task t : runtime.store.list()) {
                        if (t.bookId.equals(bookId)) next.add(t);
                    }
                    Collections.sort(next, (x, y) -> Integer.compare(x.order, y.order));
                    a.runOnUiThread(() -> {
                        if (!dialog.isShowing() || a.isDestroyed()) return;
                        tasks.clear();
                        tasks.addAll(next);
                        adapter.notifyDataSetChanged();
                        list.postDelayed(this, 1500);
                    });
                });
            }
        };
        list.post(refresh);
        dialog.setOnDismissListener(d -> list.removeCallbacks(refresh));
    }

    private static void taskActions(Activity a, Task task) {
        DownloadRuntime runtime = DownloadRuntime.get(a);
        boolean completed = task.state == State.COMPLETED;
        String[] options = completed
                ? new String[]{"删除此章", "重新下载此章"}
                : new String[]{"暂停", "继续 / 重试", "取消并清理本章"};

        ArrayAdapter<String> menu = new ArrayAdapter<String>(a, android.R.layout.simple_list_item_1, options) {
            @Override public View getView(int i, View old, ViewGroup parent) {
                TextView view = (TextView) super.getView(i, old, parent);
                view.setTextColor(UIHelpers.TEXT);
                view.setPadding(dp(a, 16), dp(a, 12), dp(a, 16), dp(a, 12));
                return view;
            }
        };

        AlertDialog dialog = new AlertDialog.Builder(a)
                .setCustomTitle(label(a, task.title, 17, UIHelpers.TEXT))
                .setAdapter(menu, (d, which) -> {
                    if (completed) {
                        confirm(a, "删除此章的下载文件？", "阅读进度和在线收藏会保留。", () -> {
                            runtime.io.execute(() -> {
                                try {
                                    runtime.deleteChapter(task.id);
                                    if (which == 1) {
                                        Task retry = task.copy();
                                        retry.state = State.QUEUED;
                                        retry.generation = DownloadCoordinator.nextGeneration();
                                        retry.failures = 0;
                                        retry.donePages = 0;
                                        retry.totalPages = 0;
                                        retry.bytes = 0;
                                        retry.error = "";
                                        retry.nextAttempt = 0;
                                        synchronized (runtime.queue) {
                                            if (runtime.store.get(retry.id) == null) runtime.store.save(retry);
                                        }
                                    }
                                    a.runOnUiThread(() -> {
                                        if (which == 1) startService(a);
                                    });
                                } catch (Exception error) {
                                    a.runOnUiThread(() -> toast(a, "删除未完成，请重试"));
                                }
                            });
                        });
                    } else if (which == 0) {
                        runtime.queue.pause(task.id);
                    } else if (which == 1) {
                        if (task.state == State.DELETING) {
                            runtime.io.execute(() -> {
                                try {
                                    runtime.deleteChapter(task.id);
                                } catch (Exception error) {
                                    a.runOnUiThread(() -> toast(a, "清理未完成，请重试"));
                                }
                            });
                        } else {
                            runtime.queue.resume(task.id);
                            startService(a);
                        }
                    } else {
                        confirm(a, "取消本章下载？", "只清理这章的未完成文件，其他已下载章节会保留。", () -> {
                            runtime.queue.cancel(task.id);
                            runtime.io.execute(() -> {
                                try {
                                    runtime.cancel(task.id);
                                } catch (Exception error) {
                                    a.runOnUiThread(() -> toast(a, "清理未完成，请重试"));
                                }
                            });
                        });
                    }
                })
                .create();
        theme(dialog, a);
        dialog.show();
    }

    public static View storage(Activity a, Runnable back, Runnable refresh) {
        DownloadRuntime runtime = DownloadRuntime.get(a);
        LinearLayout page = column(a);
        page.setBackgroundColor(UIHelpers.BG);
        page.setPadding(dp(a, 16), dp(a, 12), dp(a, 16), dp(a, 16));

        header(a, page, "本地存储管理", back);

        // Wi-Fi Switch Card
        LinearLayout wifiCard = UIHelpers.card(a);
        wifiCard.setPadding(dp(a, 14), dp(a, 10), dp(a, 14), dp(a, 10));
        LinearLayout wifiRow = row(a);
        LinearLayout wifiText = column(a);
        wifiText.addView(UIHelpers.text(a, "仅 Wi-Fi 下载", 14, UIHelpers.TEXT, Typeface.BOLD));
        wifiText.addView(UIHelpers.text(a, "未连接 Wi-Fi 时自动暂停下载任务", 11, UIHelpers.TEXT3, Typeface.NORMAL),
                UIHelpers.marginTop(-1, dp(a, 2)));
        wifiRow.addView(wifiText, UIHelpers.weight(1));
        Switch wifi = new Switch(a);
        wifi.setChecked(runtime.wifiOnly());
        wifi.setOnCheckedChangeListener((v, value) -> {
            runtime.wifiOnly(value);
            if (runtime.hasPending()) startService(a);
        });
        wifiRow.addView(wifi);
        wifiCard.addView(wifiRow);
        page.addView(wifiCard, UIHelpers.marginBottom(-1, dp(a, 10)));

        // Storage Statistics Card
        LinearLayout statsCard = UIHelpers.card(a);
        statsCard.setPadding(dp(a, 14), dp(a, 12), dp(a, 14), dp(a, 12));
        statsCard.addView(UIHelpers.text(a, "存储空间统计", 14, UIHelpers.TEXT, Typeface.BOLD));
        TextView totals = UIHelpers.text(a, "正在统计存储占用...", 12, UIHelpers.TEXT2, Typeface.NORMAL);
        statsCard.addView(totals, UIHelpers.marginTop(-1, dp(a, 6)));
        page.addView(statsCard, UIHelpers.marginBottom(-1, dp(a, 12)));

        // Books list section
        TextView listHeader = UIHelpers.text(a, "已保存的本地漫画与离线下载", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        page.addView(listHeader, UIHelpers.marginBottom(-1, dp(a, 6)));

        Set<String> selected = new HashSet<>();
        ListView list = new ListView(a);
        list.setDivider(null);
        list.setDividerHeight(dp(a, 6));
        list.setVerticalScrollBarEnabled(false);
        page.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));

        List<LocalModels.Book> books = runtime.library.store.listBooks();
        list.setAdapter(new BaseAdapter() {
            @Override public int getCount() { return books.size(); }
            @Override public Object getItem(int i) { return books.get(i); }
            @Override public long getItemId(int i) { return i; }
            @Override public View getView(int i, View old, ViewGroup p) {
                LocalModels.Book book = books.get(i);
                LinearLayout card = row(a);
                card.setPadding(dp(a, 12), dp(a, 8), dp(a, 12), dp(a, 8));
                card.setBackground(UIHelpers.round(UIHelpers.CARD, dp(a, 8), UIHelpers.BORDER));

                CheckBox check = new CheckBox(a);
                check.setButtonTintList(ColorStateList.valueOf(UIHelpers.ACCENT));
                check.setChecked(selected.contains(book.id));
                check.setOnCheckedChangeListener((v, value) -> {
                    if (value) selected.add(book.id);
                    else selected.remove(book.id);
                });
                card.addView(check);

                LinearLayout textCol = column(a);
                textCol.setPadding(dp(a, 4), 0, 0, 0);
                TextView title = UIHelpers.text(a, book.getDisplayTitle(), 14, UIHelpers.TEXT, Typeface.BOLD);
                title.setSingleLine(true);
                title.setEllipsize(TextUtils.TruncateAt.END);
                textCol.addView(title);

                String badge = LocalModels.isDownload(book) ? "离线下载" : "本地导入";
                TextView sub = UIHelpers.text(a, badge + " · " + format(book.totalSize), 11, UIHelpers.TEXT3, Typeface.NORMAL);
                textCol.addView(sub, UIHelpers.marginTop(-1, dp(a, 2)));
                card.addView(textCol, UIHelpers.weight(1));

                card.setOnClickListener(v -> check.toggle());
                return card;
            }
        });

        // Bottom Actions: 清理可再生缓存 & 删除选中漫画
        LinearLayout actions = row(a);
        actions.setPadding(0, dp(a, 10), 0, 0);
        Button clearCacheBtn = UIHelpers.secondaryButton(a, "清理缓存");
        clearCacheBtn.setOnClickListener(v -> {
            runtime.io.execute(() -> {
                runtime.library.storage.clearDerivedPagesCache();
                a.runOnUiThread(refresh);
            });
        });
        actions.addView(clearCacheBtn, UIHelpers.buttonWeight(a, 1));
        actions.addView(UIHelpers.space(a, dp(a, 8), 1));

        Button deleteSelectedBtn = UIHelpers.secondaryButton(a, "删除选中");
        deleteSelectedBtn.setOnClickListener(v -> {
            if (selected.isEmpty()) {
                toast(a, "先选择需要删除的漫画");
                return;
            }
            confirm(a, "删除选中的本地漫画？", "仅删除 App 中的副本，原文件、在线收藏和阅读记录不受影响。", () -> {
                Set<String> ids = new HashSet<>(selected);
                runtime.io.execute(() -> {
                    int failures = 0;
                    for (String id : ids) {
                        LocalModels.Book b = runtime.library.store.getBook(id);
                        if (b == null) continue;
                        boolean ok = LocalModels.isDownload(b)
                                ? runtime.deleteBook(id)
                                : runtime.library.store.deleteBook(id, runtime.library.storage);
                        if (!ok) failures++;
                    }
                    final int errors = failures;
                    a.runOnUiThread(() -> {
                        toast(a, errors == 0 ? "已清理本地副本" : "部分文件删除失败，请重试");
                        refresh.run();
                    });
                });
            });
        });
        actions.addView(deleteSelectedBtn, UIHelpers.buttonWeight(a, 1));
        page.addView(actions);

        runtime.io.execute(() -> {
            long imported = DownloadRuntime.size(runtime.library.storage.getImportsDir());
            long downloaded = DownloadRuntime.size(runtime.library.storage.getDownloadsDir());
            long cache = DownloadRuntime.size(runtime.library.storage.getPagesCacheDir());
            long usable = runtime.library.storage.getUsableSpace();
            a.runOnUiThread(() -> {
                if (!a.isDestroyed()) {
                    totals.setText("本地导入: " + format(imported) + "  ·  离线下载: " + format(downloaded)
                            + "\n可清缓存: " + format(cache) + "  ·  剩余空间: " + format(usable));
                }
            });
        });

        return page;
    }

    private static void addToolChip(Activity a, LinearLayout row, String text, Runnable run) {
        TextView chip = UIHelpers.text(a, text, 12, UIHelpers.ACCENT, Typeface.BOLD);
        chip.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(a, 6), UIHelpers.BORDER));
        chip.setPadding(dp(a, 10), dp(a, 5), dp(a, 10), dp(a, 5));
        chip.setGravity(Gravity.CENTER);
        chip.setOnClickListener(w -> run.run());
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1);
        lp.rightMargin = dp(a, 6);
        row.addView(chip, lp);
    }

    private static void confirm(Activity a, String title, String message, Runnable action) {
        LinearLayout content = row(a);
        content.setPadding(dp(a, 16), dp(a, 14), dp(a, 16), dp(a, 10));
        ImageView rem = new ImageView(a);
        rem.setImageResource(R.drawable.rem_empty);
        content.addView(rem, new LinearLayout.LayoutParams(dp(a, 56), dp(a, 56)));

        LinearLayout copy = column(a);
        copy.setPadding(dp(a, 12), 0, 0, 0);
        TextView titleView = UIHelpers.text(a, title, 16, UIHelpers.TEXT, Typeface.BOLD);
        copy.addView(titleView);
        TextView msgView = UIHelpers.text(a, message, 13, UIHelpers.TEXT2, Typeface.NORMAL);
        copy.addView(msgView, UIHelpers.marginTop(-1, dp(a, 4)));
        content.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));

        AlertDialog dialog = new AlertDialog.Builder(a)
                .setView(content)
                .setNegativeButton("取消", null)
                .setPositiveButton("确认", (d, w) -> action.run())
                .create();
        theme(dialog, a);
        dialog.show();
    }

    private static void theme(AlertDialog dialog, Activity a) {
        dialog.setOnShowListener(d -> {
            if (dialog.getWindow() != null) {
                dialog.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, dp(a, 16), Color.TRANSPARENT));
            }
            Button positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            Button negative = dialog.getButton(AlertDialog.BUTTON_NEGATIVE);
            if (positive != null) positive.setTextColor(UIHelpers.ACCENT);
            if (negative != null) negative.setTextColor(UIHelpers.TEXT3);
        });
    }

    public static String state(Task t) {
        switch (t.state) {
            case QUEUED: return "等待下载";
            case RESOLVING: return t.isFileTask?"获取文件":"读取章节";
            case DOWNLOADING: return "下载中";
            case VERIFYING: return t.isFileTask?"校验与解析中":"校验中";
            case COMPLETED: return "已完成";
            case PAUSED_USER: return "已暂停";
            case WAITING_NETWORK: return "等待 Wi-Fi / 网络";
            case WAITING_VERIFICATION: return "等待站源验证";
            case FAILED: return "失败 · 可重试";
            case CANCELLED: return "已取消";
            default: return "删除中 · 失败可重试";
        }
    }

    public static String format(long bytes) {
        return bytes < 1024 * 1024
                ? String.format(Locale.CHINA, "%.1f KB", bytes / 1024d)
                : String.format(Locale.CHINA, "%.1f MB", bytes / 1048576d);
    }

    private static int dp(Activity a, int value) { return UIHelpers.dp(a, value); }
    private static LinearLayout column(Activity a) {
        LinearLayout l = new LinearLayout(a);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }
    private static LinearLayout row(Activity a) {
        LinearLayout l = new LinearLayout(a);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }
    private static TextView label(Activity a, String text, int size, int color) {
        TextView v = UIHelpers.text(a, text, size, color, Typeface.NORMAL);
        v.setPadding(dp(a, 12), dp(a, 8), dp(a, 12), dp(a, 8));
        return v;
    }
    private static void header(Activity a, LinearLayout page, String title, Runnable back) {
        LinearLayout row = row(a);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(a, 6), 0, dp(a, 8));

        TextView titleView = UIHelpers.text(a, title, 20, UIHelpers.TEXT, Typeface.BOLD);
        titleView.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        row.addView(titleView, UIHelpers.weight(1));

        page.addView(row);
    }
    private static void toast(Activity a, String message) {
        if (!a.isDestroyed()) Toast.makeText(a, message, Toast.LENGTH_SHORT).show();
    }
}
