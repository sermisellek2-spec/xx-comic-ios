package com.xxcomic;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.ScrollView;
import android.widget.TextView;
import com.xxcomic.source.ComicModels.ComicSummary;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Draggable source picker, with its own scroll surface and no network requests. */
final class SourceSwitchSheet extends PopupWindow {
    interface CoverFactory { View create(ComicSummary comic); }
    interface Selection { void select(ComicSummary comic); }
    interface SourceName { String get(String id); }

    private final Activity activity;
    private final FrameLayout overlay;
    private final View backdrop;
    private final Panel panel;
    private final ScrollView scroll;
    private final LinearLayout list;
    private final TextView title;
    private final TextView status;
    private final CoverFactory covers;
    private final Selection selection;
    private final SourceName names;
    private final Map<String, Row> rows = new LinkedHashMap<>();
    private int collapsedHeight, expandedHeight;
    private ValueAnimator resize;
    private final boolean isReader;
    private boolean closing;

    SourceSwitchSheet(Activity activity, View anchor, CoverFactory covers, SourceName names, Selection selection) {
        this(activity, anchor, false, covers, names, selection);
    }

    SourceSwitchSheet(Activity activity, View anchor, boolean isReader, CoverFactory covers, SourceName names, Selection selection) {
        super(activity);
        this.activity = activity;
        this.isReader = isReader;
        this.covers = covers;
        this.names = names;
        this.selection = selection;
        overlay = new FrameLayout(activity);
        backdrop = new View(activity);
        backdrop.setBackgroundColor(Color.argb(110, 10, 24, 37));
        overlay.addView(backdrop, new FrameLayout.LayoutParams(-1, -1));
        panel = new Panel();
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), 0, dp(16), dp(12));
        GradientDrawable background = new GradientDrawable();
        background.setColor(isReader ? Color.parseColor("#1C2128") : UIHelpers.CARD);
        float radius = dp(16);
        background.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        panel.setBackground(background);
        panel.setClipToOutline(true);
        FrameLayout handleHost = new FrameLayout(activity);
        View handle = new View(activity);
        handle.setBackground(UIHelpers.round(isReader ? Color.parseColor("#444C56") : UIHelpers.BORDER, dp(2), Color.TRANSPARENT));
        handleHost.addView(handle, new FrameLayout.LayoutParams(dp(32), dp(4), Gravity.CENTER));
        handleHost.setContentDescription("展开或收起换源列表");
        handleHost.setOnClickListener(v -> animateHeight(panel.getHeight() < expandedHeight ? expandedHeight : collapsedHeight));
        panel.addView(handleHost, new LinearLayout.LayoutParams(-1, dp(24)));
        LinearLayout header = new LinearLayout(activity);
        header.setGravity(Gravity.CENTER_VERTICAL);
        title = UIHelpers.text(activity, "换源列表", 16, isReader ? Color.parseColor("#E6EDF3") : UIHelpers.TEXT, Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        View close = UIHelpers.vectorIconButton(activity, R.drawable.ic_close, isReader ? Color.parseColor("#8B949E") : UIHelpers.TEXT3, 10);
        close.setContentDescription("关闭换源列表");
        close.setOnClickListener(v -> dismiss());
        header.addView(close, new LinearLayout.LayoutParams(dp(44), dp(44)));
        panel.addView(header, new LinearLayout.LayoutParams(-1, dp(44)));
        status = UIHelpers.text(activity, "", 11, isReader ? Color.parseColor("#8B949E") : UIHelpers.TEXT3, Typeface.NORMAL);
        status.setPadding(0, 0, 0, dp(8));
        panel.addView(status);
        scroll = new ScrollView(activity);
        scroll.setFillViewport(false);
        scroll.setVerticalScrollBarEnabled(false);
        list = new LinearLayout(activity);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list);
        panel.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        int height = Math.max(1, anchor.getHeight());
        collapsedHeight = Math.round(height * .55f);
        expandedHeight = Math.round(height * .92f);
        overlay.addView(panel, new FrameLayout.LayoutParams(-1, collapsedHeight, Gravity.BOTTOM));
        setContentView(overlay);
        setWidth(-1);
        setHeight(-1);
        setFocusable(true);
        setInputMethodMode(INPUT_METHOD_NOT_NEEDED);
        setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        backdrop.setOnClickListener(v -> dismiss());
    }

    void show(View anchor) {
        showAtLocation(anchor, Gravity.BOTTOM, 0, 0);
        overlay.post(() -> {
            if (!isShowing() || closing) return;
            collapsedHeight = Math.round(overlay.getHeight() * .55f);
            expandedHeight = Math.round(overlay.getHeight() * .92f);
            setPanelHeight(collapsedHeight);
            panel.setTranslationY(collapsedHeight);
            panel.animate().translationY(0).setDuration(240).setInterpolator(new DecelerateInterpolator()).start();
            backdrop.setAlpha(0f);
            backdrop.animate().alpha(1f).setDuration(200).start();
        });
    }

    void update(List<ComicSummary> options, String selectedId, String pendingSource, boolean searching) {
        if (closing) return;
        title.setText("换源列表（" + options.size() + "）");
        status.setText(searching ? "正在查找同名漫画…" : options.size() == 1 ? "暂未找到其他同名站源" : "");
        status.setVisibility(status.getText().length() == 0 ? View.GONE : View.VISIBLE);
        int scrollY = scroll.getScrollY();
        list.removeAllViews();
        for (ComicSummary comic : options) {
            Row row = rows.get(comic.sourceId);
            if (row == null || !row.comic.comicId.equals(comic.comicId)) {
                row = new Row(comic);
                rows.put(comic.sourceId, row);
            }
            boolean selected = comic.comicId.equals(selectedId);
            row.mark.setText(selected ? "✓" : "○");
            row.mark.setTextColor(selected ? UIHelpers.ON_ACCENT : (isReader ? Color.parseColor("#8B949E") : UIHelpers.TEXT3));
            row.mark.setBackground(UIHelpers.round(selected ? UIHelpers.ACCENT : Color.TRANSPARENT, dp(12), Color.TRANSPARENT));
            row.name.setText(names.get(comic.sourceId) + (comic.sourceId.equals(pendingSource) ? " · 切换中…" : ""));
            row.name.setTextColor(comic.sourceId.equals(pendingSource) ? UIHelpers.ACCENT : (isReader ? Color.parseColor("#8B949E") : UIHelpers.TEXT2));
            row.view.setSelected(selected);
            row.view.setContentDescription(comic.title + "，" + names.get(comic.sourceId) + (selected ? "，当前站源" : "，点击切换"));
            list.addView(row.view);
        }
        scroll.post(() -> { if (isShowing()) scroll.scrollTo(0, scrollY); });
    }

    private final class Row {
        final ComicSummary comic;
        final LinearLayout view;
        final TextView mark, name;
        Row(ComicSummary comic) {
            this.comic = comic;
            view = new LinearLayout(activity);
            view.setGravity(Gravity.CENTER_VERTICAL);
            view.setPadding(dp(4), dp(10), dp(4), dp(10));
            view.setClickable(true);
            view.setFocusable(true);
            UIHelpers.tapFeedback(view);
            mark = UIHelpers.text(activity, "", 16, UIHelpers.ACCENT, Typeface.BOLD);
            mark.setGravity(Gravity.CENTER);
            view.addView(mark, new LinearLayout.LayoutParams(dp(24), dp(24)));
            LinearLayout.LayoutParams coverParams = new LinearLayout.LayoutParams(dp(48), dp(66));
            coverParams.setMargins(dp(14), 0, dp(14), 0);
            view.addView(covers.create(comic), coverParams);
            LinearLayout info = new LinearLayout(activity);
            info.setOrientation(LinearLayout.VERTICAL);
            TextView comicTitle = UIHelpers.text(activity, comic.title, 14, isReader ? Color.parseColor("#E6EDF3") : UIHelpers.TEXT, Typeface.NORMAL);
            comicTitle.setMaxLines(2);
            comicTitle.setEllipsize(android.text.TextUtils.TruncateAt.END);
            info.addView(comicTitle);
            name = UIHelpers.text(activity, "", 12, isReader ? Color.parseColor("#8B949E") : UIHelpers.TEXT2, Typeface.NORMAL);
            info.addView(name, UIHelpers.marginTop(-1, dp(6)));
            view.addView(info, new LinearLayout.LayoutParams(0, -2, 1));
            view.setOnClickListener(v -> { dismiss(); selection.select(comic); });
        }
    }

    static int settledHeight(int height, int upwardDrag, int collapsed, int expanded) {
        if (height < collapsed * .65f) return 0;
        if (Math.abs(upwardDrag) > collapsed * .08f) return upwardDrag > 0 ? expanded : collapsed;
        return height > (collapsed + expanded) / 2 ? expanded : collapsed;
    }

    private void setPanelHeight(int height) {
        panel.getLayoutParams().height = height;
        panel.requestLayout();
    }

    private void animateHeight(int height) {
        if (resize != null) resize.cancel();
        resize = ValueAnimator.ofInt(panel.getHeight(), height);
        resize.setDuration(220);
        resize.setInterpolator(new DecelerateInterpolator());
        resize.addUpdateListener(a -> setPanelHeight((int)a.getAnimatedValue()));
        resize.start();
    }

    @Override public void dismiss() {
        if (!isShowing() || closing) return;
        closing = true;
        if (resize != null) resize.cancel();
        backdrop.animate().alpha(0f).setDuration(180).start();
        panel.animate().translationY(panel.getHeight()).setDuration(200).withEndAction(this::dismissImmediately).start();
    }

    void dismissImmediately() {
        closing = true;
        if (resize != null) resize.cancel();
        panel.animate().withEndAction(null).cancel();
        backdrop.animate().cancel();
        super.dismiss();
    }

    private int dp(int value) { return UIHelpers.dp(activity, value); }

    private final class Panel extends LinearLayout {
        private float downY, downX;
        private int downHeight;
        private boolean fromHeader, dragging;
        Panel() { super(activity); }

        @Override public boolean onInterceptTouchEvent(MotionEvent event) {
            if (closing) return true;
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                if (resize != null) resize.cancel();
                panel.animate().cancel();
                panel.setTranslationY(0);
                downY = event.getRawY();
                downX = event.getRawX();
                downHeight = getHeight();
                fromHeader = event.getY() < scroll.getTop();
                dragging = false;
            } else if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
                float delta = event.getRawY() - downY;
                if (Math.abs(delta) > ViewConfiguration.get(activity).getScaledTouchSlop()
                        && Math.abs(delta) > Math.abs(event.getRawX() - downX)
                        && (fromHeader || (delta < 0 && getHeight() < expandedHeight)
                        || (delta > 0 && !scroll.canScrollVertically(-1)))) {
                    dragging = true;
                    return true;
                }
            }
            return false;
        }

        @Override public boolean onTouchEvent(MotionEvent event) {
            if (closing) return true;
            int delta = Math.round(downY - event.getRawY());
            if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
                dragging = true;
                setPanelHeight(Math.max(dp(140), Math.min(expandedHeight, downHeight + delta)));
            } else if (event.getActionMasked() == MotionEvent.ACTION_UP || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
                if (dragging) {
                    int target = settledHeight(getHeight(), delta, collapsedHeight, expandedHeight);
                    if (target == 0) dismiss(); else animateHeight(target);
                } else performClick();
                dragging = false;
            }
            return true;
        }

        @Override public boolean performClick() { return super.performClick(); }
    }
}
