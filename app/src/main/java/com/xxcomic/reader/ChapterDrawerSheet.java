package com.xxcomic.reader;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.xxcomic.DataHelpers;
import com.xxcomic.UIHelpers;
import com.xxcomic.source.ComicModels;

import java.util.ArrayList;
import java.util.List;

/**
 * Bottom Sheet chapter catalog drawer with two-stage height (starts half-screen ~55%,
 * pull up to expand to ~92%, tap handle to toggle, pull down to collapse/dismiss)
 * and auto-scroll-to-top alignment of currently reading chapter.
 * Adapts background color for Reader (dark translucent #1C2128) vs Detail (theme aware).
 */
public final class ChapterDrawerSheet extends PopupWindow {

    public interface OnChapterSelectedListener {
        void onChapterSelected(int chapterIndex);
    }

    public interface VolumeProvider {
        String getVolumeTitle(String chapterId);
    }

    public interface OrderChangeListener {
        void onOrderChanged(boolean isDesc);
    }

    private final Activity activity;
    private final FrameLayout overlay;
    private final View backdrop;
    private final Panel panel;
    private final LinearLayout contentContainer;
    private final TextView headerTitleView;
    private final TextView orderBtn;
    private final boolean isReader;
    private final boolean isDarkReader;
    private final OnChapterSelectedListener selectionListener;
    private final VolumeProvider volumeProvider;
    private OrderChangeListener orderChangeListener;
    private Runnable dismissListener;

    private List<ComicModels.Chapter> chapters;
    private List<Integer> orderIndexes;
    private int currentChapterIndex;
    private boolean hasCurrent;
    private boolean isDesc;

    private int collapsedHeight, expandedHeight;
    private ValueAnimator resize;
    private boolean closing;

    private RecyclerView recyclerView;
    private LinearLayoutManager layoutManager;
    private ChapterAdapter adapter;

    public ChapterDrawerSheet(Activity activity, List<ComicModels.Chapter> chapters,
                              int currentChapterIndex, boolean hasCurrent, boolean isReader,
                              boolean isDesc, VolumeProvider volumeProvider,
                              OnChapterSelectedListener listener) {
        this(activity, chapters, currentChapterIndex, hasCurrent, isReader, true, isDesc, volumeProvider, listener);
    }

    public ChapterDrawerSheet(Activity activity, List<ComicModels.Chapter> chapters,
                              int currentChapterIndex, boolean hasCurrent, boolean isReader,
                              boolean isDarkReader, boolean isDesc, VolumeProvider volumeProvider,
                              OnChapterSelectedListener listener) {
        super(activity);
        this.activity = activity;
        this.chapters = chapters != null ? chapters : new ArrayList<>();
        this.currentChapterIndex = currentChapterIndex;
        this.hasCurrent = hasCurrent;
        this.isReader = isReader;
        this.isDarkReader = isDarkReader;
        this.isDesc = isDesc;
        this.volumeProvider = volumeProvider;
        this.selectionListener = listener;

        overlay = new FrameLayout(activity);
        backdrop = new View(activity);
        backdrop.setBackgroundColor(isReader ? (isDarkReader ? Color.argb(130, 0, 0, 0) : Color.argb(90, 0, 0, 0)) : Color.argb(110, 10, 24, 37));
        overlay.addView(backdrop, new FrameLayout.LayoutParams(-1, -1));
        backdrop.setOnClickListener(v -> dismiss());

        panel = new Panel();
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(0, 0, 0, dp(12));

        // Drawer background:
        // Reader: dark translucent #1C2128 (~92% opacity) or light translucent #FFFFFF (~97% opacity)
        // Detail: follows theme mode (UIHelpers.CARD)
        GradientDrawable panelBg = new GradientDrawable();
        float radius = dp(16);
        panelBg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        if (isReader) {
            panelBg.setColor(isDarkReader ? Color.argb(235, 28, 33, 40) : Color.argb(248, 255, 255, 255));
        } else {
            panelBg.setColor(UIHelpers.CARD);
        }
        panel.setBackground(panelBg);
        panel.setClipToOutline(true);

        // Top drag handle bar (clickable to toggle between 55% and 92%)
        FrameLayout handleHost = new FrameLayout(activity);
        View handle = new View(activity);
        handle.setBackground(UIHelpers.round(isReader ? (isDarkReader ? Color.parseColor("#444C56") : Color.parseColor("#D0D7DE")) : UIHelpers.BORDER, dp(2), Color.TRANSPARENT));
        handleHost.addView(handle, new FrameLayout.LayoutParams(dp(32), dp(4), Gravity.CENTER));
        handleHost.setContentDescription("展开或收起章节目录");
        handleHost.setOnClickListener(v -> animateHeight(panel.getHeight() < expandedHeight ? expandedHeight : collapsedHeight));
        panel.addView(handleHost, new LinearLayout.LayoutParams(-1, dp(22)));

        // Header: fixed "全部章节" and order toggle ("正序" / "倒序")
        LinearLayout header = new LinearLayout(activity);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(20), dp(6), dp(20), dp(10));

        headerTitleView = UIHelpers.text(activity, "全部章节", 16,
                isReader ? (isDarkReader ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328")) : UIHelpers.TEXT,
                Typeface.BOLD);
        header.addView(headerTitleView, new LinearLayout.LayoutParams(0, -2, 1f));
        headerTitleView.setOnClickListener(v -> toggleOrder());

        orderBtn = UIHelpers.text(activity, isDesc ? "倒序" : "正序", 12,
                isReader ? (isDarkReader ? Color.parseColor("#8B949E") : Color.parseColor("#656D76")) : UIHelpers.TEXT3,
                Typeface.NORMAL);
        orderBtn.setPadding(dp(10), dp(4), dp(10), dp(4));
        orderBtn.setBackground(UIHelpers.round(isReader ? (isDarkReader ? Color.argb(40, 255, 255, 255) : Color.argb(20, 0, 0, 0)) : UIHelpers.CARD_SOFT, dp(12), Color.TRANSPARENT));
        orderBtn.setOnClickListener(v -> toggleOrder());
        header.addView(orderBtn);

        panel.addView(header, new LinearLayout.LayoutParams(-1, -2));

        contentContainer = new LinearLayout(activity);
        contentContainer.setOrientation(LinearLayout.VERTICAL);
        panel.addView(contentContainer, new LinearLayout.LayoutParams(-1, 0, 1f));

        if (!this.chapters.isEmpty()) {
            setupRecyclerView();
        }

        int screenH = activity.getResources().getDisplayMetrics().heightPixels;
        collapsedHeight = Math.round(screenH * 0.55f);
        expandedHeight = Math.round(screenH * 0.92f);
        overlay.addView(panel, new FrameLayout.LayoutParams(-1, collapsedHeight, Gravity.BOTTOM));

        setContentView(overlay);
        setWidth(-1);
        setHeight(-1);
        setFocusable(true);
        setInputMethodMode(INPUT_METHOD_NOT_NEEDED);
        setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        setOnDismissListener(() -> {
            if (dismissListener != null) {
                dismissListener.run();
            }
        });
    }

    public void setOrderChangeListener(OrderChangeListener listener) {
        this.orderChangeListener = listener;
    }

    public void setDismissListener(Runnable onDismiss) {
        this.dismissListener = onDismiss;
    }

    public void show() {
        if (activity.isFinishing() || activity.isDestroyed()) return;
        View decor = activity.getWindow() != null ? activity.getWindow().getDecorView() : null;
        if (decor != null) {
            show(decor);
        }
    }

    public void show(View anchor) {
        if (activity.isFinishing() || activity.isDestroyed()) return;
        if (anchor == null) return;
        closing = false;
        showAtLocation(anchor, Gravity.BOTTOM, 0, 0);
        overlay.post(() -> {
            if (!isShowing() || closing) return;
            int h = overlay.getHeight();
            if (h <= 0) h = activity.getResources().getDisplayMetrics().heightPixels;
            collapsedHeight = Math.round(h * 0.55f);
            expandedHeight = Math.round(h * 0.92f);
            setPanelHeight(collapsedHeight);
            panel.setTranslationY(collapsedHeight);
            panel.animate().translationY(0).setDuration(240).setInterpolator(new DecelerateInterpolator()).start();
            backdrop.setAlpha(0f);
            backdrop.animate().alpha(1f).setDuration(200).start();
            if (recyclerView != null) {
                scrollToTargetPosition();
            }
        });
    }

    @Override
    public void dismiss() {
        if (!isShowing() || closing) return;
        closing = true;
        if (resize != null) resize.cancel();
        backdrop.animate().alpha(0f).setDuration(180).start();
        panel.animate().translationY(panel.getHeight()).setDuration(200)
                .withEndAction(this::dismissImmediately).start();
    }

    public void dismissImmediately() {
        closing = true;
        if (resize != null) resize.cancel();
        panel.animate().withEndAction(null).cancel();
        backdrop.animate().cancel();
        try {
            super.dismiss();
        } catch (Exception ignored) {}
    }

    public static int settledHeight(int height, int upwardDrag, int collapsed, int expanded) {
        if (height < collapsed * 0.65f) return 0;
        if (Math.abs(upwardDrag) > collapsed * 0.08f) return upwardDrag > 0 ? expanded : collapsed;
        return height > (collapsed + expanded) / 2 ? expanded : collapsed;
    }

    private void setPanelHeight(int height) {
        ViewGroup.LayoutParams lp = panel.getLayoutParams();
        if (lp != null) {
            lp.height = height;
            panel.requestLayout();
        }
    }

    private void animateHeight(int height) {
        if (resize != null) resize.cancel();
        resize = ValueAnimator.ofInt(panel.getHeight(), height);
        resize.setDuration(220);
        resize.setInterpolator(new DecelerateInterpolator());
        resize.addUpdateListener(a -> setPanelHeight((int) a.getAnimatedValue()));
        resize.start();
    }

    public void updateChapters(List<ComicModels.Chapter> newChapters, int newCurrentChapterIndex, boolean newHasCurrent) {
        this.chapters = newChapters != null ? newChapters : new ArrayList<>();
        this.currentChapterIndex = newCurrentChapterIndex;
        this.hasCurrent = newHasCurrent;
        contentContainer.removeAllViews();
        if (!this.chapters.isEmpty()) {
            setupRecyclerView();
            scrollToTargetPosition();
        }
    }

    public void showLoadingState(String message, String subMessage) {
        contentContainer.removeAllViews();
        LinearLayout box = new LinearLayout(activity);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(24), dp(48), dp(24), dp(48));

        ProgressBar pb = new ProgressBar(activity);
        box.addView(pb, new LinearLayout.LayoutParams(dp(36), dp(36)));

        TextView msgView = UIHelpers.text(activity, message, 14,
                isReader ? (isDarkReader ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328")) : UIHelpers.TEXT, Typeface.NORMAL);
        msgView.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams msgLp = new LinearLayout.LayoutParams(-2, -2);
        msgLp.topMargin = dp(14);
        box.addView(msgView, msgLp);

        if (!TextUtils.isEmpty(subMessage)) {
            TextView subView = UIHelpers.text(activity, subMessage, 12,
                    isReader ? (isDarkReader ? Color.parseColor("#8B949E") : Color.parseColor("#656D76")) : UIHelpers.TEXT3, Typeface.NORMAL);
            subView.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams subLp = new LinearLayout.LayoutParams(-2, -2);
            subLp.topMargin = dp(6);
            box.addView(subView, subLp);
        }

        contentContainer.addView(box, new LinearLayout.LayoutParams(-1, -1));
    }

    public void showErrorState(String message, String buttonText, Runnable retryAction) {
        contentContainer.removeAllViews();
        LinearLayout box = new LinearLayout(activity);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(24), dp(48), dp(24), dp(48));

        TextView msgView = UIHelpers.text(activity, message, 14,
                isReader ? (isDarkReader ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328")) : UIHelpers.TEXT, Typeface.NORMAL);
        msgView.setGravity(Gravity.CENTER);
        box.addView(msgView);

        if (!TextUtils.isEmpty(buttonText) && retryAction != null) {
            TextView retryBtn = UIHelpers.text(activity, buttonText, 13,
                    Color.WHITE, Typeface.BOLD);
            retryBtn.setGravity(Gravity.CENTER);
            retryBtn.setPadding(dp(20), dp(8), dp(20), dp(8));
            retryBtn.setBackground(UIHelpers.round(UIHelpers.ACCENT, dp(6), Color.TRANSPARENT));
            retryBtn.setOnClickListener(v -> retryAction.run());

            LinearLayout.LayoutParams btnLp = new LinearLayout.LayoutParams(-2, -2);
            btnLp.topMargin = dp(16);
            box.addView(retryBtn, btnLp);
        }

        contentContainer.addView(box, new LinearLayout.LayoutParams(-1, -1));
    }

    private void setupRecyclerView() {
        contentContainer.removeAllViews();
        orderIndexes = DataHelpers.chapterOrder(isDesc, chapters.size());

        recyclerView = new RecyclerView(activity);
        layoutManager = new LinearLayoutManager(activity);
        recyclerView.setLayoutManager(layoutManager);
        recyclerView.setHasFixedSize(true);
        recyclerView.setVerticalScrollBarEnabled(false);
        recyclerView.setOverScrollMode(View.OVER_SCROLL_NEVER);

        adapter = new ChapterAdapter(activity, chapters, orderIndexes, currentChapterIndex,
                hasCurrent, isReader, isDarkReader, volumeProvider, index -> {
            dismiss();
            if (selectionListener != null) {
                selectionListener.onChapterSelected(index);
            }
        });
        recyclerView.setAdapter(adapter);

        contentContainer.addView(recyclerView, new LinearLayout.LayoutParams(-1, -1));
    }

    private void toggleOrder() {
        if (chapters.isEmpty()) return;
        isDesc = !isDesc;
        if (orderBtn != null) {
            orderBtn.setText(isDesc ? "倒序" : "正序");
        }
        if (orderChangeListener != null) {
            orderChangeListener.onOrderChanged(isDesc);
        }
        orderIndexes = DataHelpers.chapterOrder(isDesc, chapters.size());
        if (adapter != null) {
            adapter.setOrderIndexes(orderIndexes);
        }
        scrollToTargetPosition();
    }

    private void scrollToTargetPosition() {
        if (recyclerView == null || layoutManager == null || orderIndexes == null || orderIndexes.isEmpty()) {
            return;
        }
        int targetPosition = -1;
        if (hasCurrent && currentChapterIndex >= 0) {
            targetPosition = orderIndexes.indexOf(currentChapterIndex);
        }
        if (targetPosition < 0) {
            targetPosition = 0;
        }
        final int pos = targetPosition;
        layoutManager.scrollToPositionWithOffset(pos, 0);
        recyclerView.post(() -> layoutManager.scrollToPositionWithOffset(pos, 0));
        recyclerView.postDelayed(() -> layoutManager.scrollToPositionWithOffset(pos, 0), 60);
    }

    private int dp(int value) {
        return UIHelpers.dp(activity, value);
    }

    private final class Panel extends LinearLayout {
        private float downY, downX;
        private int downHeight;
        private boolean fromHeader, dragging;

        Panel() {
            super(activity);
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent event) {
            if (closing) return true;
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                if (resize != null) resize.cancel();
                panel.animate().cancel();
                panel.setTranslationY(0);
                downY = event.getRawY();
                downX = event.getRawX();
                downHeight = getHeight();
                fromHeader = event.getY() < contentContainer.getTop();
                dragging = false;
            } else if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
                float delta = event.getRawY() - downY;
                boolean canScrollUp = recyclerView != null && recyclerView.canScrollVertically(-1);
                if (Math.abs(delta) > ViewConfiguration.get(activity).getScaledTouchSlop()
                        && Math.abs(delta) > Math.abs(event.getRawX() - downX)
                        && (fromHeader || (delta < 0 && getHeight() < expandedHeight)
                        || (delta > 0 && !canScrollUp))) {
                    dragging = true;
                    return true;
                }
            }
            return false;
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
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

        @Override
        public boolean performClick() {
            return super.performClick();
        }
    }

    private static class ChapterAdapter extends RecyclerView.Adapter<ChapterViewHolder> {
        private final Activity activity;
        private final List<ComicModels.Chapter> chapters;
        private List<Integer> orderIndexes;
        private final int currentChapterIndex;
        private final boolean hasCurrent;
        private final boolean isReader;
        private final boolean isDarkReader;
        private final VolumeProvider volumeProvider;
        private final OnChapterSelectedListener listener;

        ChapterAdapter(Activity activity, List<ComicModels.Chapter> chapters, List<Integer> orderIndexes,
                       int currentChapterIndex, boolean hasCurrent, boolean isReader, boolean isDarkReader,
                       VolumeProvider volumeProvider, OnChapterSelectedListener listener) {
            this.activity = activity;
            this.chapters = chapters;
            this.orderIndexes = orderIndexes;
            this.currentChapterIndex = currentChapterIndex;
            this.hasCurrent = hasCurrent;
            this.isReader = isReader;
            this.isDarkReader = isDarkReader;
            this.volumeProvider = volumeProvider;
            this.listener = listener;
        }

        void setOrderIndexes(List<Integer> newOrderIndexes) {
            this.orderIndexes = newOrderIndexes;
            notifyDataSetChanged();
        }

        @NonNull
        @Override
        public ChapterViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            return new ChapterViewHolder(activity, isReader, isDarkReader);
        }

        @Override
        public void onBindViewHolder(@NonNull ChapterViewHolder holder, int position) {
            int chapterIndex = orderIndexes.get(position);
            ComicModels.Chapter chapter = chapters.get(chapterIndex);
            boolean isCurrent = hasCurrent && (chapterIndex == currentChapterIndex);

            String volumeTitle = null;
            if (volumeProvider != null) {
                String currVol = volumeProvider.getVolumeTitle(chapter.chapterId);
                String prevVol = position == 0 ? null : volumeProvider.getVolumeTitle(chapters.get(orderIndexes.get(position - 1)).chapterId);
                if (currVol != null && (prevVol == null || !currVol.equals(prevVol))) {
                    volumeTitle = currVol;
                }
            }

            holder.bind(chapter, isCurrent, volumeTitle, v -> {
                if (listener != null) {
                    listener.onChapterSelected(chapterIndex);
                }
            });
        }

        @Override
        public int getItemCount() {
            return orderIndexes != null ? orderIndexes.size() : 0;
        }
    }

    private static class ChapterViewHolder extends RecyclerView.ViewHolder {
        private final LinearLayout container;
        private final TextView volumeHeading;
        private final LinearLayout row;
        private final View indicator;
        private final TextView titleView;
        private final boolean isReader;
        private final boolean isDarkReader;

        ChapterViewHolder(Context context, boolean isReader, boolean isDarkReader) {
            super(new LinearLayout(context));
            this.isReader = isReader;
            this.isDarkReader = isDarkReader;
            container = (LinearLayout) itemView;
            container.setOrientation(LinearLayout.VERTICAL);
            container.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));

            volumeHeading = new TextView(context);
            volumeHeading.setTextSize(12);
            volumeHeading.setTextColor(UIHelpers.ACCENT);
            volumeHeading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            volumeHeading.setPadding(UIHelpers.dp(context, 20), UIHelpers.dp(context, 12),
                    UIHelpers.dp(context, 20), UIHelpers.dp(context, 4));
            volumeHeading.setVisibility(View.GONE);
            container.addView(volumeHeading);

            row = new LinearLayout(context);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setMinimumHeight(UIHelpers.dp(context, 46));
            row.setPadding(UIHelpers.dp(context, 18), UIHelpers.dp(context, 10),
                    UIHelpers.dp(context, 18), UIHelpers.dp(context, 10));

            TypedValue outValue = new TypedValue();
            context.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, outValue, true);
            row.setBackgroundResource(outValue.resourceId);

            // Left vertical blue indicator bar (▌)
            indicator = new View(context);
            GradientDrawable indicatorBg = new GradientDrawable();
            indicatorBg.setColor(isReader && !isDarkReader ? Color.parseColor("#0969DA") : Color.parseColor("#2E79E6"));
            indicatorBg.setCornerRadius(UIHelpers.dp(context, 2));
            indicator.setBackground(indicatorBg);

            int indWidth = Math.max(1, Math.round(context.getResources().getDisplayMetrics().density * 3.5f));
            LinearLayout.LayoutParams indicatorLp = new LinearLayout.LayoutParams(
                    indWidth, UIHelpers.dp(context, 18));
            indicatorLp.rightMargin = UIHelpers.dp(context, 12);
            row.addView(indicator, indicatorLp);

            titleView = new TextView(context);
            titleView.setTextSize(14.5f);
            titleView.setSingleLine(true);
            titleView.setEllipsize(TextUtils.TruncateAt.END);
            titleView.setIncludeFontPadding(false);
            row.addView(titleView, new LinearLayout.LayoutParams(0, -2, 1f));

            container.addView(row, new LinearLayout.LayoutParams(-1, -2));
        }

        void bind(ComicModels.Chapter chapter, boolean isCurrent, String volumeTitle, View.OnClickListener onClick) {
            if (volumeTitle != null) {
                volumeHeading.setText(volumeTitle);
                volumeHeading.setVisibility(View.VISIBLE);
            } else {
                volumeHeading.setVisibility(View.GONE);
            }

            indicator.setVisibility(isCurrent ? View.VISIBLE : View.INVISIBLE);
            titleView.setText(chapter.title);

            if (isReader) {
                titleView.setTextColor(isCurrent
                        ? (isDarkReader ? Color.WHITE : Color.parseColor("#0969DA"))
                        : (isDarkReader ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328")));
            } else {
                titleView.setTextColor(isCurrent ? UIHelpers.ACCENT : UIHelpers.TEXT);
            }
            titleView.setTypeface(Typeface.DEFAULT, isCurrent ? Typeface.BOLD : Typeface.NORMAL);

            row.setOnClickListener(onClick);
        }
    }
}
