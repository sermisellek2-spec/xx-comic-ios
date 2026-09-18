package com.xxcomic.local;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.recyclerview.widget.ItemTouchHelper;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.recyclerview.widget.SimpleItemAnimator;
import com.xxcomic.R;
import com.xxcomic.UIHelpers;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Edits the existing volume index; styled as a stable, smooth bottom drawer. */
public final class VolumeManagerSheet extends Dialog {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static volatile VolumeManagerSheet activeInstance;

    private final Activity activity;
    private final LocalModels.Book book;
    private final LocalLibraryStore store;
    private final LocalStorageManager storage;
    private final LocalDetailView.Listener listener;
    private final List<LocalModels.Volume> volumes = new ArrayList<>();
    private final Rows adapter = new Rows();
    private final RecyclerView list;
    private final TextView status;
    private final TextView volumeCountBadge;
    private final ItemTouchHelper touch;
    private final android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());
    private LocalModels.Volume pendingDeletedVolume;
    private int pendingDeletedIndex = -1;
    private Runnable pendingDeleteCommitRunnable;
    private LinearLayout undoBar;
    private TextView undoText;
    private boolean busy, dragging, changed, notified;
    private String draggedId;
    private int originalPosition;
    private LocalModels.Book latest;

    public static VolumeManagerSheet getActiveInstance() {
        return activeInstance;
    }

    public String getBookId() {
        return book != null ? book.id : "";
    }

    VolumeManagerSheet(Activity activity, LocalModels.Book book, LocalLibraryStore store,
                       LocalStorageManager storage, LocalDetailView.Listener listener) {
        super(activity);
        this.activity = activity;
        this.book = book;
        this.store = store;
        this.storage = storage;
        this.listener = listener;
        this.latest = book;

        requestWindowFeature(Window.FEATURE_NO_TITLE);
        setCanceledOnTouchOutside(true);
        volumes.addAll(store.getVolumes(book.id));

        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(10), dp(16), dp(16));

        GradientDrawable panelBg = new GradientDrawable();
        float radius = dp(18);
        panelBg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        panelBg.setColor(UIHelpers.CARD);
        panel.setBackground(panelBg);

        // Top drag handle bar
        View pullBar = new View(activity);
        pullBar.setBackground(UIHelpers.round(UIHelpers.BORDER, dp(2), Color.TRANSPARENT));
        LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(dp(36), dp(4));
        barParams.gravity = Gravity.CENTER_HORIZONTAL;
        barParams.bottomMargin = dp(12);
        panel.addView(pullBar, barParams);

        // Header row
        LinearLayout headerRow = new LinearLayout(activity);
        headerRow.setOrientation(LinearLayout.HORIZONTAL);
        headerRow.setGravity(Gravity.CENTER_VERTICAL);

        TextView titleView = UIHelpers.text(activity, "管理分卷", 17, UIHelpers.TEXT, Typeface.BOLD);
        headerRow.addView(titleView);

        volumeCountBadge = UIHelpers.text(activity, "共 " + volumes.size() + " 卷", 11, UIHelpers.TEXT3, Typeface.NORMAL);
        volumeCountBadge.setPadding(dp(6), dp(2), dp(6), dp(2));
        volumeCountBadge.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, dp(4), Color.TRANSPARENT));
        LinearLayout.LayoutParams badgeParams = new LinearLayout.LayoutParams(-2, -2);
        badgeParams.leftMargin = dp(8);
        headerRow.addView(volumeCountBadge, badgeParams);

        headerRow.addView(new View(activity), new LinearLayout.LayoutParams(0, 1, 1f));

        if (LocalModels.SOURCE_TYPE_IMPORT.equals(book.sourceType)) {
            TextView addBtn = UIHelpers.text(activity, "+ 添加分卷", 12, UIHelpers.ACCENT, Typeface.BOLD);
            addBtn.setPadding(dp(12), dp(6), dp(12), dp(6));
            addBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(14), Color.TRANSPARENT));
            addBtn.setOnClickListener(v -> {
                if (listener != null) {
                    listener.onAddVolumes(latest != null ? latest : book);
                }
            });
            headerRow.addView(addBtn);
        }
        panel.addView(headerRow, new LinearLayout.LayoutParams(-1, -2));

        // Subtitle
        TextView subtitleView = UIHelpers.text(activity, "拖动右侧手柄排序；移除分卷仅清理 App 副本，原文件保留。",
                12, UIHelpers.TEXT3, Typeface.NORMAL);
        panel.addView(subtitleView, UIHelpers.marginTop(-1, dp(6)));

        // Status indicator
        status = UIHelpers.text(activity, "", 12, UIHelpers.ACCENT, Typeface.NORMAL);
        status.setPadding(dp(8), dp(4), dp(8), dp(4));
        status.setVisibility(View.GONE);
        panel.addView(status, UIHelpers.marginTop(-1, dp(2)));

        // RecyclerView for volumes
        list = new RecyclerView(activity);
        list.setLayoutManager(new LinearLayoutManager(activity));
        list.setAdapter(adapter);
        list.setVerticalScrollBarEnabled(false);
        RecyclerView.ItemAnimator animator = list.getItemAnimator();
        if (animator instanceof SimpleItemAnimator) {
            ((SimpleItemAnimator) animator).setSupportsChangeAnimations(false);
        }

        touch = new ItemTouchHelper(new ItemTouchHelper.SimpleCallback(ItemTouchHelper.UP | ItemTouchHelper.DOWN, 0) {
            @Override public boolean isLongPressDragEnabled() { return !busy; }
            @Override public int getMovementFlags(RecyclerView rv, RecyclerView.ViewHolder holder) {
                return busy ? 0 : super.getMovementFlags(rv, holder);
            }
            @Override public boolean onMove(RecyclerView rv, RecyclerView.ViewHolder from, RecyclerView.ViewHolder to) {
                int a = from.getBindingAdapterPosition(), b = to.getBindingAdapterPosition();
                if (busy || a < 0 || b < 0) return false;
                volumes.add(b, volumes.remove(a));
                adapter.notifyItemMoved(a, b);
                return true;
            }
            @Override public void onSwiped(RecyclerView.ViewHolder holder, int direction) { }
            @Override public void onSelectedChanged(RecyclerView.ViewHolder holder, int state) {
                super.onSelectedChanged(holder, state);
                if (state == ItemTouchHelper.ACTION_STATE_DRAG && holder != null) {
                    int position = holder.getBindingAdapterPosition();
                    if (position < 0) return;
                    dragging = true;
                    originalPosition = position;
                    draggedId = volumes.get(position).id;
                    holder.itemView.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(8), UIHelpers.ACCENT));
                } else if (state == ItemTouchHelper.ACTION_STATE_IDLE && dragging) {
                    dragging = false;
                    String id = draggedId;
                    int target = -1;
                    for (int i = 0; i < volumes.size(); i++) if (volumes.get(i).id.equals(id)) target = i;
                    if (target >= 0 && target != originalPosition) {
                        int position = target;
                        change(() -> { store.moveVolumeToPosition(book.id, id, position); return true; });
                    }
                    list.post(adapter::notifyDataSetChanged);
                }
            }
            @Override public void clearView(RecyclerView rv, RecyclerView.ViewHolder holder) {
                super.clearView(rv, holder);
                holder.itemView.setBackground(UIHelpers.round(UIHelpers.SURFACE, dp(8), Color.TRANSPARENT));
            }
        });
        touch.attachToRecyclerView(list);
        panel.addView(list, new LinearLayout.LayoutParams(-1, 0, 1f));

        undoBar = new LinearLayout(activity);
        undoBar.setOrientation(LinearLayout.HORIZONTAL);
        undoBar.setGravity(Gravity.CENTER_VERTICAL);
        undoBar.setPadding(dp(12), dp(8), dp(12), dp(8));
        undoBar.setBackground(UIHelpers.round(UIHelpers.SURFACE, dp(10), UIHelpers.BORDER));
        undoBar.setVisibility(View.GONE);

        ImageView remIcon = new ImageView(activity);
        remIcon.setImageResource(R.drawable.rem_empty);
        remIcon.setScaleType(ImageView.ScaleType.FIT_CENTER);
        undoBar.addView(remIcon, new LinearLayout.LayoutParams(dp(26), dp(26)));

        undoText = UIHelpers.text(activity, "", 12, UIHelpers.TEXT, Typeface.BOLD);
        undoText.setMaxLines(1);
        undoText.setEllipsize(TextUtils.TruncateAt.END);
        LinearLayout.LayoutParams textLp = new LinearLayout.LayoutParams(0, -2, 1f);
        textLp.leftMargin = dp(8);
        undoBar.addView(undoText, textLp);

        TextView undoBtn = UIHelpers.text(activity, "撤销", 12, UIHelpers.ACCENT, Typeface.BOLD);
        undoBtn.setPadding(dp(12), dp(6), dp(12), dp(6));
        undoBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(12), Color.TRANSPARENT));
        undoBtn.setOnClickListener(v -> performUndo());
        undoBar.addView(undoBtn);

        LinearLayout.LayoutParams undoParams = new LinearLayout.LayoutParams(-1, -2);
        undoParams.topMargin = dp(8);
        panel.addView(undoBar, undoParams);

        panel.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(panel, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setOnDismissListener(d -> {
            commitPendingDelete();
            if (activeInstance == this) {
                activeInstance = null;
            }
            notifyDetail();
        });
    }

    @Override protected void onCreate(android.os.Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window window = getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int height = (int) (activity.getResources().getDisplayMetrics().heightPixels * 0.72f);
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, height);
            window.setGravity(Gravity.BOTTOM);
            window.setDimAmount(0.4f);
            window.setWindowAnimations(R.style.DownloadSheetAnimation);
        }
    }

    @Override public void show() {
        activeInstance = this;
        super.show();
        Window window = getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int height = (int) (activity.getResources().getDisplayMetrics().heightPixels * 0.72f);
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, height);
            window.setGravity(Gravity.BOTTOM);
            window.setDimAmount(0.4f);
            window.setWindowAnimations(R.style.DownloadSheetAnimation);
        }
    }

    @Override public void dismiss() {
        commitPendingDelete();
        super.dismiss();
        if (activeInstance == this) {
            activeInstance = null;
        }
    }

    @Override protected void onStop() {
        commitPendingDelete();
        super.onStop();
        if (activeInstance == this) {
            activeInstance = null;
        }
    }

    public void reloadVolumes() {
        commitPendingDelete();
        IO.execute(() -> {
            List<LocalModels.Volume> updated = null;
            LocalModels.Book updatedBook = latest;
            try {
                updated = store.getVolumes(book.id);
                updatedBook = store.getBook(book.id);
            } catch (Exception e) {
                android.util.Log.w("VolumeManagerSheet", "Failed to reload volumes", e);
            }
            List<LocalModels.Volume> rows = updated;
            LocalModels.Book result = updatedBook;
            activity.runOnUiThread(() -> {
                if (activity.isDestroyed() || activity.isFinishing()) return;
                changed = true;
                latest = result != null ? result : latest;
                if (rows != null) {
                    volumes.clear();
                    volumes.addAll(rows);
                    adapter.notifyDataSetChanged();
                    volumeCountBadge.setText("共 " + volumes.size() + " 卷");
                }
                status.setText(volumes.isEmpty() ? "暂无分卷" : "");
                status.setVisibility(volumes.isEmpty() ? View.VISIBLE : View.GONE);
            });
        });
    }

    private interface Change { boolean run() throws Exception; }

    private void change(Change operation) {
        if (busy) return;
        busy = true;
        status.setText("正在保存…");
        status.setVisibility(View.VISIBLE);
        IO.execute(() -> {
            boolean ok = false;
            List<LocalModels.Volume> updated = null;
            LocalModels.Book updatedBook = latest;
            try {
                ok = operation.run();
            } catch (Exception e) { android.util.Log.w("VolumeManagerSheet", "Volume operation failed", e); }
            try {
                updated = store.getVolumes(book.id);
                updatedBook = store.getBook(book.id);
            } catch (Exception e) { ok = false; }
            boolean success = ok;
            List<LocalModels.Volume> rows = updated;
            LocalModels.Book result = updatedBook;
            activity.runOnUiThread(() -> {
                busy = false;
                changed = true;
                latest = result;
                if (activity.isDestroyed() || activity.isFinishing()) return;
                if (rows != null) {
                    volumes.clear();
                    volumes.addAll(rows);
                    adapter.notifyDataSetChanged();
                    volumeCountBadge.setText("共 " + volumes.size() + " 卷");
                }
                status.setText(volumes.isEmpty() ? "暂无分卷" : "");
                status.setVisibility(volumes.isEmpty() ? View.VISIBLE : View.GONE);
                if (!success) Toast.makeText(activity, "操作未完成，请重试", Toast.LENGTH_SHORT).show();
                if (!isShowing()) notifyDetail();
            });
        });
    }

    private void notifyDetail() {
        if (busy || dragging || !changed || notified || activity.isDestroyed() || activity.isFinishing()) return;
        notified = true;
        if (listener != null) {
            if (latest == null) listener.onBookDeleted(book);
            else listener.onBookRenamed(latest);
        }
    }

    private void removeVolumeWithUndo(LocalModels.Volume volume, int position) {
        if (busy || dragging) return;
        commitPendingDelete();

        pendingDeletedVolume = volume;
        pendingDeletedIndex = position;

        volumes.remove(position);
        adapter.notifyItemRemoved(position);
        adapter.notifyItemRangeChanged(position, volumes.size() - position);
        volumeCountBadge.setText("共 " + volumes.size() + " 卷");

        status.setText(volumes.isEmpty() ? "暂无分卷" : "");
        status.setVisibility(volumes.isEmpty() ? View.VISIBLE : View.GONE);

        if (undoBar != null && undoText != null) {
            undoText.setText("已移出《" + volume.title + "》");
            undoBar.setAlpha(0f);
            undoBar.setVisibility(View.VISIBLE);
            undoBar.animate().alpha(1f).setDuration(180).start();
        }

        pendingDeleteCommitRunnable = this::commitPendingDelete;
        handler.postDelayed(pendingDeleteCommitRunnable, 3500L);
    }

    private void performUndo() {
        if (pendingDeletedVolume == null) return;
        if (pendingDeleteCommitRunnable != null) {
            handler.removeCallbacks(pendingDeleteCommitRunnable);
            pendingDeleteCommitRunnable = null;
        }
        LocalModels.Volume restored = pendingDeletedVolume;
        int insertPos = Math.max(0, Math.min(pendingDeletedIndex, volumes.size()));
        pendingDeletedVolume = null;
        pendingDeletedIndex = -1;

        volumes.add(insertPos, restored);
        adapter.notifyItemInserted(insertPos);
        adapter.notifyItemRangeChanged(insertPos, volumes.size() - insertPos);
        volumeCountBadge.setText("共 " + volumes.size() + " 卷");

        status.setText(volumes.isEmpty() ? "暂无分卷" : "");
        status.setVisibility(volumes.isEmpty() ? View.VISIBLE : View.GONE);

        if (undoBar != null) {
            undoBar.animate().alpha(0f).setDuration(160).withEndAction(() -> undoBar.setVisibility(View.GONE)).start();
        }
    }

    private void commitPendingDelete() {
        if (pendingDeleteCommitRunnable != null) {
            handler.removeCallbacks(pendingDeleteCommitRunnable);
            pendingDeleteCommitRunnable = null;
        }
        if (pendingDeletedVolume != null) {
            LocalModels.Volume volume = pendingDeletedVolume;
            pendingDeletedVolume = null;
            pendingDeletedIndex = -1;
            if (undoBar != null) undoBar.setVisibility(View.GONE);
            change(() -> store.deleteVolume(book.id, volume.id, storage));
        }
    }

    private final class Row extends RecyclerView.ViewHolder {
        final TextView indexBadge, title;
        final ImageView handle, remove;

        Row(LinearLayout row) {
            super(row);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setMinimumHeight(dp(54));
            row.setPadding(dp(12), dp(8), dp(8), dp(8));
            row.setBackground(UIHelpers.round(UIHelpers.SURFACE, dp(10), UIHelpers.BORDER));

            RecyclerView.LayoutParams params = new RecyclerView.LayoutParams(-1, -2);
            params.topMargin = dp(4);
            params.bottomMargin = dp(4);
            row.setLayoutParams(params);

            indexBadge = UIHelpers.text(activity, "", 11, UIHelpers.TEXT3, Typeface.BOLD);
            indexBadge.setGravity(Gravity.CENTER);
            indexBadge.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, dp(11), Color.TRANSPARENT));
            row.addView(indexBadge, new LinearLayout.LayoutParams(dp(22), dp(22)));

            LinearLayout titleCol = new LinearLayout(activity);
            titleCol.setOrientation(LinearLayout.VERTICAL);
            titleCol.setPadding(dp(10), 0, dp(6), 0);

            title = UIHelpers.text(activity, "", 13, UIHelpers.TEXT, Typeface.NORMAL);
            title.setMaxLines(2);
            title.setEllipsize(TextUtils.TruncateAt.END);
            titleCol.addView(title);
            row.addView(titleCol, UIHelpers.weight(1));

            remove = UIHelpers.vectorIconButton(activity, R.drawable.ic_trash, UIHelpers.DANGER, 6);
            remove.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, dp(16), Color.TRANSPARENT));
            row.addView(remove, new LinearLayout.LayoutParams(dp(32), dp(32)));

            row.addView(UIHelpers.space(activity, dp(8), 1));

            handle = UIHelpers.vectorIconButton(activity, R.drawable.ic_menu, UIHelpers.TEXT3, 6);
            handle.setBackground(UIHelpers.round(UIHelpers.CARD_SOFT, dp(16), Color.TRANSPARENT));
            row.addView(handle, new LinearLayout.LayoutParams(dp(32), dp(32)));

            handle.setOnTouchListener((v, event) -> {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN && !busy && getBindingAdapterPosition() >= 0) {
                    touch.startDrag(this);
                }
                if (event.getActionMasked() == MotionEvent.ACTION_UP) v.performClick();
                return true;
            });
            remove.setOnClickListener(v -> {
                int position = getBindingAdapterPosition();
                if (position >= 0 && position < volumes.size()) {
                    removeVolumeWithUndo(volumes.get(position), position);
                }
            });
        }
    }

    private final class Rows extends RecyclerView.Adapter<Row> {
        @Override public Row onCreateViewHolder(ViewGroup parent, int type) {
            return new Row(new LinearLayout(activity));
        }

        @Override public void onBindViewHolder(Row row, int position) {
            LocalModels.Volume volume = volumes.get(position);
            row.indexBadge.setText(String.valueOf(position + 1));
            row.title.setText(volume.title);
            row.handle.setContentDescription("拖动调整顺序：" + volume.title);
            row.remove.setContentDescription("移除 " + volume.title);
        }

        @Override public int getItemCount() { return volumes.size(); }
    }

    private int dp(int value) { return UIHelpers.dp(activity, value); }
}
