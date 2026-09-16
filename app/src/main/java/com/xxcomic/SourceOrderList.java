package com.xxcomic;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.recyclerview.widget.ItemTouchHelper;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.List;

/** One scrolling surface; only the handle starts dragging, never the source switch. */
final class SourceOrderList extends RecyclerView {
    interface Factory { View create(); }
    interface OnOrderChanged { void save(List<String> ids); }
    static final class Row {
        final String id;
        final Factory factory;
        Row(String id, Factory factory) { this.id = id; this.factory = factory; }
    }

    private final List<Row> rows;
    private final Activity activity;
    private final ItemTouchHelper touchHelper;
    private boolean moved;

    SourceOrderList(Activity context, List<Row> rows, OnOrderChanged onChanged) {
        super(context);
        activity = context;
        this.rows = new ArrayList<>(rows);
        setLayoutManager(new LinearLayoutManager(context));
        setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(context, 8), Color.TRANSPARENT));
        setClipToOutline(true);
        setAdapter(new RowsAdapter());
        touchHelper = new ItemTouchHelper(new ItemTouchHelper.SimpleCallback(
                ItemTouchHelper.UP | ItemTouchHelper.DOWN, 0) {
            @Override public boolean isLongPressDragEnabled() { return false; }
            @Override public boolean isItemViewSwipeEnabled() { return false; }
            @Override public boolean onMove(RecyclerView list, ViewHolder from, ViewHolder to) {
                int start = from.getBindingAdapterPosition(), end = to.getBindingAdapterPosition();
                if (start == NO_POSITION || end == NO_POSITION || start == end) return false;
                SourceOrderList.this.rows.add(end, SourceOrderList.this.rows.remove(start));
                getAdapter().notifyItemMoved(start, end);
                moved = true;
                // Persist each accepted move, including if the app is closed during a drag.
                List<String> ids = new ArrayList<>();
                for (Row row : SourceOrderList.this.rows) ids.add(row.id);
                onChanged.save(ids);
                return true;
            }
            @Override public void onSwiped(ViewHolder holder, int direction) { }
            @Override public void clearView(RecyclerView list, ViewHolder holder) {
                super.clearView(list, holder);
                if (moved) {
                    holder.itemView.announceForAccessibility("站源顺序已保存");
                    moved = false;
                }
            }
        });
        touchHelper.attachToRecyclerView(this);
    }

    private final class RowsAdapter extends Adapter<RowHolder> {
        @Override public RowHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            LinearLayout wrap = new LinearLayout(getContext());
            wrap.setOrientation(LinearLayout.VERTICAL);
            wrap.setBackgroundColor(UIHelpers.CARD);
            wrap.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));
            LinearLayout line = new LinearLayout(getContext());
            line.setGravity(Gravity.CENTER_VERTICAL);
            TextView handle = UIHelpers.text(activity, "≡", 24, UIHelpers.TEXT3, Typeface.NORMAL);
            handle.setGravity(Gravity.CENTER);
            handle.setContentDescription("拖动调整站源顺序");
            line.addView(handle, new LinearLayout.LayoutParams(UIHelpers.dp(getContext(), 40), UIHelpers.dp(getContext(), 52)));
            LinearLayout body = new LinearLayout(getContext());
            line.addView(body, new LinearLayout.LayoutParams(0, -2, 1));
            wrap.addView(line);
            wrap.addView(UIHelpers.divider(activity));
            RowHolder holder = new RowHolder(wrap, body);
            handle.setOnTouchListener((v, event) -> {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN
                        && holder.getBindingAdapterPosition() != NO_POSITION) {
                    touchHelper.startDrag(holder);
                }
                return true;
            });
            return holder;
        }
        @Override public void onBindViewHolder(RowHolder holder, int position) {
            holder.itemView.setTag("source-row:" + rows.get(position).id);
            holder.body.removeAllViews();
            holder.body.addView(rows.get(position).factory.create(), new LinearLayout.LayoutParams(-1, -2));
        }
        @Override public int getItemCount() { return rows.size(); }
    }

    private static final class RowHolder extends ViewHolder {
        final LinearLayout body;
        RowHolder(View view, LinearLayout body) { super(view); this.body = body; }
    }
}
