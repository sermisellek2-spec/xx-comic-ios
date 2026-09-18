package com.xxcomic.local;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.recyclerview.widget.ItemTouchHelper;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.xxcomic.R;
import com.xxcomic.UIHelpers;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Edits the existing volume index; refreshes the detail once the user leaves the sheet. */
final class VolumeManagerSheet extends Dialog {
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private final Activity activity;
    private final LocalModels.Book book;
    private final LocalLibraryStore store;
    private final LocalStorageManager storage;
    private final LocalDetailView.Listener listener;
    private final List<LocalModels.Volume> volumes = new ArrayList<>();
    private final Rows adapter = new Rows();
    private final RecyclerView list;
    private final TextView status;
    private final ItemTouchHelper touch;
    private boolean busy, dragging, changed, notified;
    private String draggedId;
    private int originalPosition;
    private LocalModels.Book latest;

    VolumeManagerSheet(Activity activity, LocalModels.Book book, LocalLibraryStore store,
                       LocalStorageManager storage, LocalDetailView.Listener listener) {
        super(activity);
        this.activity = activity; this.book = book; this.store = store;
        this.storage = storage; this.listener = listener; latest = book;
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        volumes.addAll(store.getVolumes(book.id));
        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(16), dp(16), dp(20));
        panel.setBackground(UIHelpers.round(UIHelpers.CARD, dp(16), Color.TRANSPARENT));
        panel.addView(UIHelpers.text(activity, "管理分卷", 17, UIHelpers.TEXT, Typeface.BOLD));
        panel.addView(UIHelpers.text(activity, "长按分卷或拖动右侧手柄排序；移除只清理 App 副本，原文件保留。",
                12, UIHelpers.TEXT3, Typeface.NORMAL));
        status = UIHelpers.text(activity, "", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        status.setVisibility(View.GONE);
        panel.addView(status);
        list = new RecyclerView(activity);
        list.setLayoutManager(new LinearLayoutManager(activity));
        list.setAdapter(adapter);
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
                    setCancelable(false);
                    originalPosition = position;
                    draggedId = volumes.get(position).id;
                    holder.itemView.setBackground(UIHelpers.round(UIHelpers.ACCENT_SOFT, dp(8), Color.TRANSPARENT));
                } else if (state == ItemTouchHelper.ACTION_STATE_IDLE && dragging) {
                    // Freeze this drag before recovery animation: a later drag must not replace its identity.
                    dragging = false;
                    String id = draggedId;
                    int target = -1;
                    for (int i = 0; i < volumes.size(); i++) if (volumes.get(i).id.equals(id)) target = i;
                    if (target >= 0 && target != originalPosition) {
                        int position = target;
                        change(() -> { store.moveVolumeToPosition(book.id, id, position); return true; });
                    } else setCancelable(true);
                }
            }
            @Override public void clearView(RecyclerView rv, RecyclerView.ViewHolder holder) {
                super.clearView(rv, holder);
                holder.itemView.setBackgroundColor(Color.TRANSPARENT);
            }
        });
        touch.attachToRecyclerView(list);
        panel.addView(list, new LinearLayout.LayoutParams(-1,
                Math.min(dp(420), activity.getResources().getDisplayMetrics().heightPixels / 2)));
        setContentView(panel);
        setOnDismissListener(d -> notifyDetail());
    }

    @Override public void show() {
        super.show();
        Window window = getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.setLayout(-1, -2); window.setGravity(Gravity.BOTTOM);
            window.setWindowAnimations(android.R.style.Animation_InputMethod);
        }
    }

    private interface Change { boolean run() throws Exception; }

    private void change(Change operation) {
        if (busy) return;
        busy = true;
        setCancelable(false);
        status.setText("正在保存…"); status.setVisibility(View.VISIBLE);
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
                setCancelable(true);
                // Even a partial deletion may have marked a volume unavailable; reload detail on exit.
                changed = true; latest = result;
                if (activity.isDestroyed() || activity.isFinishing()) return;
                if (rows != null) { volumes.clear(); volumes.addAll(rows); adapter.notifyDataSetChanged(); }
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

    private void confirmRemoval(LocalModels.Volume volume) {
        if (busy || dragging) return;
        LinearLayout message = new LinearLayout(activity);
        message.setOrientation(LinearLayout.VERTICAL);
        message.setPadding(dp(20), dp(16), dp(20), 0);
        message.addView(UIHelpers.text(activity, "移除这一卷？", 17, UIHelpers.TEXT, Typeface.BOLD));
        message.addView(UIHelpers.text(activity, volume.title + "\n其他分卷和手机中的原文件不受影响。",
                13, UIHelpers.TEXT2, Typeface.NORMAL), UIHelpers.marginTop(-1, dp(8)));
        AlertDialog confirm = new AlertDialog.Builder(activity).setView(message).setNegativeButton("取消", null)
                .setPositiveButton("移除", (d, which) -> change(() -> store.deleteVolume(book.id, volume.id, storage))).create();
        confirm.show();
        if (confirm.getWindow() != null)
            confirm.getWindow().setBackgroundDrawable(UIHelpers.round(UIHelpers.CARD, dp(12), Color.TRANSPARENT));
        confirm.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(UIHelpers.TEXT3);
        confirm.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(UIHelpers.DANGER);
    }

    private final class Row extends RecyclerView.ViewHolder {
        final TextView title, handle;
        final ImageView remove;
        Row(LinearLayout row) {
            super(row);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setMinimumHeight(dp(52));
            row.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));
            title = UIHelpers.text(activity, "", 13, UIHelpers.TEXT, Typeface.NORMAL);
            title.setMaxLines(2);
            title.setEllipsize(android.text.TextUtils.TruncateAt.END);
            row.addView(title, UIHelpers.weight(1));
            handle = UIHelpers.text(activity, "≡", 22, UIHelpers.TEXT3, Typeface.NORMAL);
            handle.setGravity(Gravity.CENTER);
            row.addView(handle, new LinearLayout.LayoutParams(dp(48), dp(48)));
            remove = UIHelpers.vectorIconButton(activity, R.drawable.ic_trash, UIHelpers.DANGER, 14);
            row.addView(remove, new LinearLayout.LayoutParams(dp(48), dp(48)));
            handle.setOnTouchListener((v, event) -> {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN && !busy && getBindingAdapterPosition() >= 0)
                    touch.startDrag(this);
                if (event.getActionMasked() == MotionEvent.ACTION_UP) v.performClick();
                return true;
            });
            remove.setOnClickListener(v -> {
                int position = getBindingAdapterPosition();
                if (position >= 0) confirmRemoval(volumes.get(position));
            });
        }
    }

    private final class Rows extends RecyclerView.Adapter<Row> {
        @Override public Row onCreateViewHolder(ViewGroup parent, int type) { return new Row(new LinearLayout(activity)); }
        @Override public void onBindViewHolder(Row row, int position) {
            LocalModels.Volume volume = volumes.get(position);
            row.title.setText(volume.title);
            row.handle.setContentDescription("拖动调整顺序：" + volume.title);
            row.remove.setContentDescription("移除 " + volume.title);
        }
        @Override public int getItemCount() { return volumes.size(); }
    }

    private int dp(int value) { return UIHelpers.dp(activity, value); }
}
